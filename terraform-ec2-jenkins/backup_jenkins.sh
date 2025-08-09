#!/bin/bash

IP="$1"
KEY="~/.ssh/id_ed25519"  # Replace with the path to your private key

echo "🔁 Backing up Jenkins data from $IP..."

ssh -o StrictHostKeyChecking=no -i $KEY ec2-user@$IP << 'EOF'
  docker stop jenkins
  tar -czf /tmp/jenkins-home.tar.gz /var/jenkins_home
  aws s3 cp /tmp/jenkins-home.tar.gz s3://your-jenkins-backup-bucket/jenkins-home.tar.gz
EOF

echo "✅ Backup complete"
