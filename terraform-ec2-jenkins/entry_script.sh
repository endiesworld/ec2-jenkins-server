#!/bin/bash
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
docker run -d -p 8080:8080 -p 50000:50000 -d --name webserver nginx