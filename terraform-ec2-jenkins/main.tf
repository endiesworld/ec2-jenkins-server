provider "aws" {
    region = var.region
}

data "aws_vpc" "default-vpc" {
    default = true
}

data "aws_subnets" "default-subnets" {
    filter {
        name   = "vpc-id"
        values = [data.aws_vpc.default-vpc.id]
    }
}

# Pick one subnet (e.g., the first) or filter by AZ
data "aws_subnet" "chosen-subnet" {
    id = data.aws_subnets.default-subnets.ids[0] # Adjust index as needed
}

resource "aws_key_pair" "jenkins_key" {
    key_name   = var.key_name
    public_key = file(var.public_key_path)
}

resource "aws_security_group" "jenkins_sg" {
    name        = "${var.env_prefix}-jenkins-sg"
    description = "Allow SSH and Jenkins Web"

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["${var.my_IP}"]
    }

    ingress {
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["${var.my_IP}"]
    }

    ingress {
        from_port   = 50000
        to_port     = 50000
        protocol    = "tcp"
        cidr_blocks = ["${var.my_IP}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

data "aws_ami" "amazon_linux" {
    most_recent = true
    owners      = ["amazon"]

    filter {
        name   = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

resource "aws_instance" "jenkins_server" {
    ami                         = data.aws_ami.amazon_linux.id
    instance_type               = var.instance_type
    key_name                    = aws_key_pair.jenkins_key.key_name
    vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
    subnet_id                   = data.aws_subnet.chosen-subnet.id # AZ is implied by the subnet; no need to set placement
    associate_public_ip_address = true

    iam_instance_profile        = var.iam_instance_profile_name

    user_data = file("${path.module}/user_data.sh")
  
    tags = {
        Name = "${var.env_prefix}-Jenkins-server"
    }

}

resource "null_resource" "backup_trigger" {
  triggers = {
    instance_ip   = aws_instance.jenkins_server.public_ip
    backup_bucket = var.backup_bucket
    region        = var.region
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "S3_BUCKET=${self.triggers.backup_bucket} AWS_REGION=${self.triggers.region} bash backup_jenkins.sh ${self.triggers.instance_ip}"
  }
}
