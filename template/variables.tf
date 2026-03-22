variable "aws_access_key" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c7i-flex.large"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI (us-east-1)"
  type        = string
  default     = "ami-07062e2a343acc423"
}

variable "key_name" {
  description = "EC2 key pair name (must already exist in AWS)"
  type        = string
  default     = "chaves-aws"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}