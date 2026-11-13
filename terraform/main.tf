terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

variable "my_ip" {
  description = "Your public IP address in CIDR format"
  type        = string
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "jenkins_key" {
  key_name   = "vprofile-jenkins"
  public_key = file("${path.module}/vprofile-jenkins.pub")
}

resource "aws_security_group" "jenkins_sg" {
  name        = "vprofile-jenkins-sg"
  description = "Allow SSH and Jenkins access from my IP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.jenkins_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -eux

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg openjdk-21-jre docker.io

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
      -o /etc/apt/keyrings/jenkins-keyring.asc

    chmod 644 /etc/apt/keyrings/jenkins-keyring.asc

    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list

    apt-get update -y
    apt-get install -y jenkins

    systemctl enable docker
    systemctl start docker

    usermod -aG docker jenkins

    systemctl enable jenkins
    systemctl restart jenkins
  USERDATA

  tags = {
    Name = "vprofile-jenkins-server"
  }
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "ssh_command" {
  value = "ssh -i ../vprofile-jenkins ubuntu@${aws_instance.jenkins.public_ip}"
}
