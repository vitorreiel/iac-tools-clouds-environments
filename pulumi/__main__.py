import os
from pulumi_command import remote
import pulumi

config = pulumi.Config()
ec2_public_ip = config.require("ec2PublicIp")
ssh_key_path  = config.get("sshKeyPath") or "../ssh/chaves-aws.pem"

_onos_dir = os.path.join(os.path.dirname(__file__), "../sdn-topology/fat-tree/onos")

with open(os.path.join(os.path.dirname(__file__), ssh_key_path)) as f:
    private_key = f.read()

connection = remote.ConnectionArgs(
    host        = ec2_public_ip,
    user        = "ubuntu",
    private_key = private_key,
)

# ------------------------------------------------------------------
# Upload topology files
# ------------------------------------------------------------------
copy_compose = remote.CopyFile(
    "copy-docker-compose",
    connection  = connection,
    local_path  = os.path.join(_onos_dir, "docker-compose.yml"),
    remote_path = "/tmp/docker-compose.yml",
)

copy_start = remote.CopyFile(
    "copy-start-sh",
    connection  = connection,
    local_path  = os.path.join(_onos_dir, "start.sh"),
    remote_path = "/tmp/start.sh",
)

copy_topology = remote.CopyFile(
    "copy-topology-py",
    connection  = connection,
    local_path  = os.path.join(_onos_dir, "topology.py"),
    remote_path = "/tmp/topology.py",
)

# ------------------------------------------------------------------
# Install Docker and deploy topology
# ------------------------------------------------------------------
configure = remote.Command(
    "configure",
    connection = connection,
    create     = """
set -e
sudo apt-get update -y
sudo apt-get install -y linux-modules-extra-aws openvswitch-switch
sudo modprobe openvswitch
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
mkdir -p /home/ubuntu/sdn-topology/onos
mv /tmp/docker-compose.yml /home/ubuntu/sdn-topology/onos/
mv /tmp/start.sh           /home/ubuntu/sdn-topology/onos/
mv /tmp/topology.py        /home/ubuntu/sdn-topology/onos/
chmod +x /home/ubuntu/sdn-topology/onos/start.sh
chown -R ubuntu:ubuntu /home/ubuntu/sdn-topology
cd /home/ubuntu/sdn-topology/onos && sudo -u ubuntu docker compose up -d
""",
    opts = pulumi.ResourceOptions(depends_on=[copy_compose, copy_start, copy_topology]),
)

# ------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------
pulumi.export("configured_host", ec2_public_ip)
pulumi.export("onos_ui",         f"http://{ec2_public_ip}:8181/onos/ui")
