output "jenkins_public_ip" {
  description = "Public IPv4 of the Jenkins instance"
  value       = aws_instance.jenkins_server.public_ip
}

output "jenkins_public_dns" {
  description = "Public DNS name of the Jenkins instance"
  value       = aws_instance.jenkins_server.public_dns
}

# Simple SSH command (assumes your key is loaded in ssh-agent)
output "jenkins_ssh_command" {
  description = "SSH command using the default Amazon Linux 2 user"
  value       = format("ssh ec2-user@%s",
    coalesce(aws_instance.jenkins_server.public_dns, aws_instance.jenkins_server.public_ip)
  )
}


# Handy: Jenkins URL (default ports from your docker run)
output "jenkins_url" {
  description = "Jenkins UI URL"
  value       = format("http://%s:8080",
    coalesce(aws_instance.jenkins_server.public_dns, aws_instance.jenkins_server.public_ip)
  )
}
