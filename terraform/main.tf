terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

variable "my_ip" {
  type = string
}

variable "repo_url" {
  type = string
}

variable "node_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.micro"
}

data "aws_availability_zones" "az" {
  state = "available"
}

resource "random_password" "jenkins" {
  length  = 16
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name                    = "vprofile-vpc"
  cidr                    = "10.0.0.0/16"
  azs                     = slice(data.aws_availability_zones.az.names, 0, 2)
  public_subnets          = ["10.0.1.0/24", "10.0.2.0/24"]
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true
  public_subnet_tags = {
    "kubernetes.io/role/elb"             = 1
    "kubernetes.io/cluster/vprofile-new" = "shared"
  }
}

resource "aws_iam_role" "jenkins" {
  name = "vprofile-jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy" "eks" {
  name = "eks-describe"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "vprofile-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                             = "vprofile-new"
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.public_subnets
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = false

  cluster_addons = {
    aws-ebs-csi-driver = {}
  }

  access_entries = {
    jenkins = {
      principal_arn = aws_iam_role.jenkins.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  eks_managed_node_groups = {
    ng1 = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = 2
      max_size       = 2
      desired_size   = 2
      iam_role_additional_policies = {
        ebs = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

resource "aws_ecr_repository" "app" {
  name         = "vprofile-app"
  force_delete = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "jenkins" {
  key_name   = "vprofile-jenkins"
  public_key = file("${path.module}/vprofile-jenkins.pub")
}

resource "aws_security_group" "jenkins" {
  name   = "vprofile-jenkins-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
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
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = aws_key_pair.jenkins.key_name
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  user_data_replace_on_change = true
  depends_on                  = [module.eks]

  root_block_device {
    volume_size = 25
  }

  tags = {
    Name = "vprofile-jenkins"
  }

  user_data = <<-EOT
    #!/bin/bash
    exec > /var/log/jenkins-bootstrap.log 2>&1
    set -x
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /etc/apt/keyrings
    apt-get update -y
    apt-get install -y fontconfig openjdk-21-jre-headless docker.io unzip curl git
    systemctl enable --now docker
    wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
    apt-get update -y
    apt-get install -y jenkins
    systemctl stop jenkins
    curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
    usermod -aG docker jenkins
    mkdir -p /var/lib/jenkins/init.groovy.d
    cat > /var/lib/jenkins/init.groovy.d/security.groovy << 'EOF2'
    import jenkins.model.*
    import hudson.security.*
    def instance = Jenkins.getInstance()
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount("admin", "${random_password.jenkins.result}")
    instance.setSecurityRealm(realm)
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)
    instance.save()
    EOF2
    chown -R jenkins:jenkins /var/lib/jenkins
    mkdir -p /etc/systemd/system/jenkins.service.d
    cat > /etc/systemd/system/jenkins.service.d/override.conf << 'EOF2'
    [Service]
    Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
    EOF2
    systemctl daemon-reload
    systemctl start jenkins
    until curl -sf http://localhost:8080/login > /dev/null; do sleep 10; done
    curl -s -u admin:${random_password.jenkins.result} http://localhost:8080/jnlpJars/jenkins-cli.jar -o /tmp/jenkins-cli.jar
    CLI="java -jar /tmp/jenkins-cli.jar -s http://localhost:8080 -auth admin:${random_password.jenkins.result}"
    for i in 1 2 3 4 5 6 7 8 9 10; do
      $CLI install-plugin workflow-aggregator git credentials-binding -restart && break
      sleep 30
    done
    sleep 20
    until curl -sf http://localhost:8080/login > /dev/null; do sleep 10; done
    cat > /tmp/job.xml << 'EOF2'
    <flow-definition>
      <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
        <scm class="hudson.plugins.git.GitSCM">
          <configVersion>2</configVersion>
          <userRemoteConfigs>
            <hudson.plugins.git.UserRemoteConfig>
              <url>${var.repo_url}</url>
            </hudson.plugins.git.UserRemoteConfig>
          </userRemoteConfigs>
          <branches>
            <hudson.plugins.git.BranchSpec>
              <name>*/main</name>
            </hudson.plugins.git.BranchSpec>
          </branches>
        </scm>
        <scriptPath>Jenkinsfile</scriptPath>
        <lightweight>true</lightweight>
      </definition>
    </flow-definition>
    EOF2
    $CLI create-job vprofile-pipeline < /tmp/job.xml
    $CLI build vprofile-pipeline
  EOT
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_password" {
  value     = random_password.jenkins.result
  sensitive = true
}

output "ecr_url" {
  value = aws_ecr_repository.app.repository_url
}