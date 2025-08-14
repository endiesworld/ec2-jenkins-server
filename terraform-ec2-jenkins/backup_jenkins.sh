#!/usr/bin/env bash
# Usage: S3_BUCKET=<bucket> AWS_REGION=<region> [S3_PREFIX=backups] ./backup_jenkins.sh <EC2_PUBLIC_IP>
set -euo pipefail

IP="${1:?Usage: ./backup_jenkins.sh <EC2_PUBLIC_IP>}"

# --- Inputs (from local environment) ---
AWS_REGION="${AWS_REGION:?Set AWS_REGION (e.g., us-west-2)}"
S3_BUCKET_RAW="${S3_BUCKET:?Set S3_BUCKET (bucket name only; 's3://...' will be stripped)}"
S3_PREFIX="${S3_PREFIX:-backups}"

# Normalize bucket (strip scheme if someone included it)
S3_BUCKET="${S3_BUCKET_RAW#s3://}"
S3_URI="s3://${S3_BUCKET}"

# Other knobs
SSH_USER="${SSH_USER:-ec2-user}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
JENKINS_HOME="/var/jenkins_home"
CONTAINER_NAME="jenkins"

STAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
S3_KEY="${S3_PREFIX}/jenkins-home-${STAMP}.tar.gz"
S3_KEY_LATEST="${S3_PREFIX}/jenkins-home-latest.tar.gz"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ServerAliveInterval=30 -i "$SSH_KEY_PATH")

echo "Backing up ${JENKINS_HOME} from ${SSH_USER}@${IP} → ${S3_URI}/${S3_KEY}"

# Optional: quick preflight on remote
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${IP}" 'command -v docker >/dev/null || { echo "docker missing"; exit 1; }; command -v aws >/dev/null || { echo "aws cli missing"; exit 1; }'

# Pass the needed values into the remote environment, then run the script body
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${IP}" \
  "export S3_BUCKET='${S3_BUCKET}' S3_URI='${S3_URI}' S3_KEY='${S3_KEY}' S3_KEY_LATEST='${S3_KEY_LATEST}' AWS_REGION='${AWS_REGION}' JENKINS_HOME='${JENKINS_HOME}' CONTAINER_NAME='${CONTAINER_NAME}'; bash -s" <<'EOSH'
set -euo pipefail

# read from env injected above: S3_BUCKET, S3_URI, S3_KEY, S3_KEY_LATEST, AWS_REGION, JENKINS_HOME, CONTAINER_NAME

# Quiesce writes if container is running
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker stop "$CONTAINER_NAME" >/dev/null
fi

# Choose compressor
COMPRESSOR="gzip"; command -v pigz >/dev/null && COMPRESSOR="pigz"

# Stream the archive directly to S3 (no temp files)
tar -C / -cf - "${JENKINS_HOME#/}" \
  | "$COMPRESSOR" \
  | aws s3 cp - "${S3_URI}/${S3_KEY}" --region "$AWS_REGION" --only-show-errors

# Update "latest" alias and verify
aws s3 cp "${S3_URI}/${S3_KEY}" "${S3_URI}/${S3_KEY_LATEST}" --region "$AWS_REGION" --only-show-errors
aws s3api head-object --bucket "$S3_BUCKET" --key "$S3_KEY" --region "$AWS_REGION" >/dev/null

# Restart if present
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME" >/dev/null
fi

echo "OK ${S3_URI}/${S3_KEY}"
EOSH

echo "✅ Backup complete:"
echo "   ${S3_URI}/${S3_KEY}"
echo "   ${S3_URI}/${S3_KEY_LATEST} (alias)"
