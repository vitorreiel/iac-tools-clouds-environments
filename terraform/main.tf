terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

locals {
  onos_dir = "${path.module}/../sdn-topology/fat-tree/onos"
}

resource "null_resource" "deploy_topology" {
  triggers = {
    ec2_ip         = var.ec2_public_ip
    docker_compose = filemd5("${local.onos_dir}/docker-compose.yml")
    start_sh       = filemd5("${local.onos_dir}/start.sh")
    topology_py    = filemd5("${local.onos_dir}/topology.py")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = var.ec2_public_ip
    private_key = file(var.ssh_key_path)
  }

  # Upload topology files
  provisioner "file" {
    source      = "${local.onos_dir}/docker-compose.yml"
    destination = "/tmp/docker-compose.yml"
  }

  provisioner "file" {
    source      = "${local.onos_dir}/start.sh"
    destination = "/tmp/start.sh"
  }

  provisioner "file" {
    source      = "${local.onos_dir}/topology.py"
    destination = "/tmp/topology.py"
  }

  # Install Docker and deploy topology
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo apt-get update -y",
      "sudo apt-get install -y linux-modules-extra-aws openvswitch-switch",
      "sudo modprobe openvswitch",
      "sudo apt-get install -y ca-certificates curl gnupg",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo usermod -aG docker ubuntu",
      "mkdir -p /home/ubuntu/sdn-topology/onos",
      "mv /tmp/docker-compose.yml /home/ubuntu/sdn-topology/onos/",
      "mv /tmp/start.sh           /home/ubuntu/sdn-topology/onos/",
      "mv /tmp/topology.py        /home/ubuntu/sdn-topology/onos/",
      "chmod +x /home/ubuntu/sdn-topology/onos/start.sh",
      "chown -R ubuntu:ubuntu /home/ubuntu/sdn-topology",
      "cd /home/ubuntu/sdn-topology/onos && sudo -u ubuntu docker compose up -d",
    ]
  }
}
