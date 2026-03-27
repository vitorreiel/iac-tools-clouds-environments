variable "ec2_public_ip" {
  description = "Public IP of the EC2 instance to configure (from template/ output)"
  type        = string
}

variable "ssh_key_path" {
  description = "Path to the SSH private key (.pem)"
  type        = string
  default     = "../ssh/chaves-aws.pem"
}

variable "topology_dir" {
  description = "SDN topology directory (fat-tree or leaf-spine)"
  type        = string
  default     = "fat-tree"
}
