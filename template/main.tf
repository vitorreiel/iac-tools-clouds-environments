# Terraform template — creates a single EC2 instance using the default VPC.
# Run this once before using any of the IaC tools in the other directories.
#
# Credentials: copy terraform.tfvars.example to terraform.tfvars and fill in
# aws_access_key and aws_secret_key.

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

resource "random_integer" "suffix" {
  min = 1000
  max = 9999
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# ------------------------------------------------------------------
# Default VPC + subnet (no custom networking needed)
# ------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ------------------------------------------------------------------
# Security Group
# ------------------------------------------------------------------
resource "aws_security_group" "sdn" {
  name        = "sdn-topology-sg"
  description = "SDN topology: SSH, ONOS UI, OpenFlow"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ONOS UI / REST"
    from_port   = 8181
    to_port     = 8181
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenFlow (ONOS)"
    from_port   = 6653
    to_port     = 6653
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sdn-topology-sg" }
}

# ------------------------------------------------------------------
# IAM role for SSM (required for CloudFormation tool)
# ------------------------------------------------------------------
resource "aws_iam_role" "ssm" {
  name = "sdn-topology-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "sdn-topology-ssm-profile"
  role = aws_iam_role.ssm.name
}

# ------------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------------
resource "aws_instance" "sdn" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.sdn.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ssm.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "sdn-topology-${random_integer.suffix.result}" }
}
