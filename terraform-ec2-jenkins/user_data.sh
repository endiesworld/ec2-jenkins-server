#!/bin/bash
set -euo pipefail

# Log everything for post-boot debugging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# -------- One-time guard (defensive; cloud-init already runs once) --------
MARKER="/var/local/jenkins-first-boot.done"
if [ -f "$MARKER" ]; then
  echo "First-boot already completed. Exiting."
  exit 0
fi

# -------- Vars (Terraform can template these) --------
S3_BUCKET="jenkins-bucket-project-adaobi"
S3_PREFIX="backups"
AWS_REGION="us-west-2"
CONTAINER_NAME="jenkins"
JENKINS_HOME="/var/jenkins_home"

# Terraform
TF_VERSION="1.9.5"
TF_HOST_DIR="/opt/terraform/bin"

# -------- OS setup --------
yum update -y
yum install -y docker aws-cli curl unzip
systemctl enable --now docker
# Wait for Docker
timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'

# Optional: let ec2-user run docker without sudo
if id ec2-user &>/dev/null; then
  usermod -aG docker ec2-user || true
fi

# -------- Prepare volume mount --------
mkdir -p "$JENKINS_HOME"
# Jenkins image uses uid:gid 1000:1000 by default
chown -R 1000:1000 "$JENKINS_HOME"

# -------- Restore from S3 (latest alias) if present --------
LATEST_KEY="${S3_PREFIX}/jenkins-home-latest.tar.gz"
echo "Attempting restore from s3://${S3_BUCKET}/${LATEST_KEY}"

if aws s3api head-object --bucket "$S3_BUCKET" --key "$LATEST_KEY" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Found latest backup. Restoring into / ..."
  aws s3 cp "s3://${S3_BUCKET}/${LATEST_KEY}" /tmp/jenkins-home.tar.gz --region "$AWS_REGION"
  tar -tzf /tmp/jenkins-home.tar.gz | head || true     # sanity peek
  tar -xzf /tmp/jenkins-home.tar.gz -C /               # entries start with var/jenkins_home/
else
  echo "No previous backup found. Starting with a fresh Jenkins home."
fi

# --- Ensure Jenkins URL matches this instance ---
PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)
PUBLIC_BASE_URL=""
if [ -n "$PUBLIC_IP" ]; then
  PUBLIC_BASE_URL="http://${PUBLIC_IP}:8080/"
fi

mkdir -p "${JENKINS_HOME}/init.groovy.d"
cat >"${JENKINS_HOME}/init.groovy.d/00-set-url.groovy" <<'GROOVY'
import jenkins.model.*
def url = System.getenv("PUBLIC_BASE_URL")
if (url && url.trim()) {
  def jlc = JenkinsLocationConfiguration.get()
  if (jlc.getUrl() != url) { jlc.setUrl(url); jlc.save() }
}
GROOVY
chown -R 1000:1000 "${JENKINS_HOME}/init.groovy.d"

# -------- Determine Docker socket GID & plugins path --------
DOCKER_GID=$(stat -c %g /var/run/docker.sock || echo 0)

PLUGINS_SRC=""
if [ -d /usr/lib/docker/cli-plugins ]; then
  PLUGINS_SRC="/usr/lib/docker/cli-plugins"
elif [ -d /usr/libexec/docker/cli-plugins ]; then
  PLUGINS_SRC="/usr/libexec/docker/cli-plugins"
fi

# ========= Install Terraform on host (then copy into container) =========
mkdir -p "$TF_HOST_DIR"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)   TF_ARCH="linux_amd64" ;;
  aarch64)  TF_ARCH="linux_arm64" ;;
  *)        TF_ARCH="linux_amd64" ;;  # default
esac

if ! [ -x "${TF_HOST_DIR}/terraform" ] || ! "${TF_HOST_DIR}/terraform" version 2>/dev/null | grep -q "Terraform v${TF_VERSION}"; then
  echo "Installing Terraform ${TF_VERSION} (${TF_ARCH}) on host..."
  curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${TF_ARCH}.zip"
  unzip -o /tmp/terraform.zip -d "$TF_HOST_DIR"
  chmod 0755 "${TF_HOST_DIR}/terraform"
  rm -f /tmp/terraform.zip
fi
ln -sf "${TF_HOST_DIR}/terraform" /usr/local/bin/terraform
# ========================================================================

# -------- Run Jenkins container (idempotent) --------
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  -p 8080:8080 -p 50000:50000
  -v "$JENKINS_HOME:/var/jenkins_home"
  -v /var/run/docker.sock:/var/run/docker.sock
  -v /usr/bin/docker:/usr/bin/docker
  --group-add "$DOCKER_GID"
  -e "PUBLIC_BASE_URL=$PUBLIC_BASE_URL"
  --restart unless-stopped
)
# Mount CLI plugins if present (buildx, compose, etc.)
if [ -n "$PLUGINS_SRC" ]; then
  RUN_ARGS+=( -v "$PLUGINS_SRC:/usr/lib/docker/cli-plugins:ro" )
fi

docker run "${RUN_ARGS[@]}" jenkins/jenkins:lts

# -------- Copy Terraform into the container (once, at instantiation) --------
echo "Copying Terraform into Jenkins container ..."
docker cp "${TF_HOST_DIR}/terraform" "${CONTAINER_NAME}:/usr/local/bin/terraform"
# Ensure executable (need root)
docker exec -u 0 "${CONTAINER_NAME}" bash -lc 'chmod 0755 /usr/local/bin/terraform'
# Quick sanity check as jenkins user
docker exec "${CONTAINER_NAME}" bash -lc 'terraform version || which terraform'

echo "Jenkins container started. UI should be on http://${PUBLIC_IP}:8080"

# Mark one-time completion
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
