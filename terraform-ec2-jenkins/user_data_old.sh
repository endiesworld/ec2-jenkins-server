#!/bin/bash
yum update -y
yum install -y docker aws-cli

systemctl start docker
systemctl enable docker

# Create mount directory
mkdir -p /var/jenkins_home

# Restore from S3 if available. Replace <jenkins-backup-bucket-project-emmanuel> with your actual bucket name.
aws s3 cp s3://jenkins-backup-bucket-project-emmanuel/jenkins-home.tar.gz /tmp/jenkins-home.tar.gz
if [ -f /tmp/jenkins-home.tar.gz ]; then
  tar -xzf /tmp/jenkins-home.tar.gz -C /var/
  chown -R 1000:1000 /var/jenkins_home
fi

# Run Jenkins container
docker run -d \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v /var/jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts
