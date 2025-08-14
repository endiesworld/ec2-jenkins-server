#!/bin/bash
set -euo pipefail

# Log everything for post-boot debugging
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# -------- Vars injected by Terraform (recommended) --------
S3_BUCKET="jenkins-bucket-project-adaobi" # Replace with your S3 bucket name for Jenkins backups
S3_PREFIX="backups"
AWS_REGION="us-west-2"
CONTAINER_NAME="jenkins"
JENKINS_HOME="/var/jenkins_home"

# -------- OS setup --------
yum update -y
yum install -y docker aws-cli
systemctl enable --now docker
timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'

# Optional: let ec2-user run docker without sudo (for convenience)
if id ec2-user &>/dev/null; then
  usermod -aG docker ec2-user || true
fi

# -------- Prepare volume mount --------
mkdir -p "$JENKINS_HOME"
# Ensure Jenkins home ownership (container runs as uid 1000 by default)
chown -R 1000:1000 "$JENKINS_HOME"

# -------- Restore from S3 (latest alias) if present --------
LATEST_KEY="${S3_PREFIX}/jenkins-home-latest.tar.gz"
echo "Attempting restore from s3://${S3_BUCKET}/${LATEST_KEY}"

# Check if the 'latest' object exists, then stream-extract directly (no /tmp file).
if aws s3api head-object --bucket "$S3_BUCKET" --key "$LATEST_KEY" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Found latest backup. Restoring into / ..."
  aws s3 cp "s3://${S3_BUCKET}/${LATEST_KEY}" /tmp/jenkins-home.tar.gz --region "$AWS_REGION"
  tar -tzf /tmp/jenkins-home.tar.gz | head || true     # sanity peek
  tar -xzf /tmp/jenkins-home.tar.gz -C /               # because entries start with var/jenkins_home/
else
  echo "No previous backup found. Starting with a fresh Jenkins home."
fi

# --- Ensure Jenkins URL matches this instance (overrides stale value from backup) ---
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


# -------- Run Jenkins container --------
# Port 50000 is only needed for inbound agents; feel free to remove if not used.
docker run -d \
  --name "$CONTAINER_NAME" \
  -p 8080:8080 -p 50000:50000 \
  -v "$JENKINS_HOME:/var/jenkins_home" \
  -e PUBLIC_BASE_URL="$PUBLIC_BASE_URL" \
  --restart unless-stopped \
  jenkins/jenkins:lts


echo "Jenkins container started. UI should be on http://<public-ip>:8080"
