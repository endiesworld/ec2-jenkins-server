variable "region" {
  default = "us-west-2"
}

variable "avail_zone" {
  description = "Availability Zone for the EC2 instance"
  default     = "us-west-2a"
}

variable "env_prefix" {
  description = "Prefix for environment resources"
  type        = string
  
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name from S3 project"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.medium"
  
}

variable "public_key_path" {
  description = "Path to your public key"
  default     = "~/.ssh/id_rsa.pub"
}

variable "key_name" {
  description = "Name of the EC2 key pair"
  type        = string
}

variable "my_IP" {
  description = "Your IP address with CIDR notation"
  type        = string
}