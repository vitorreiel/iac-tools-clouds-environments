#!/bin/bash

set -e

EC2_IP="$1"
if [ -z "$EC2_IP" ]; then
  echo "Usage: $0 <ec2-public-ip>"
  echo "  Get the IP with: cd ../template && terraform output public_ip"
  exit 1
fi

KEY="$(cd "$(dirname "$0")" && pwd)/../ssh/chaves-aws.pem"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOPOLOGY_DIR="${TOPOLOGY_DIR:-fat-tree}"
ONOS_DIR="$SCRIPT_DIR/../sdn-topology/$TOPOLOGY_DIR/onos"

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30"

echo "==> Copying Chef cookbooks to $EC2_IP..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" \
  "sudo rm -rf /tmp/chef-cookbooks /tmp/chef-cookbooks-src /tmp/sdn-topology /tmp/chef-config && mkdir -p /tmp/chef-cookbooks /tmp/sdn-topology/$TOPOLOGY_DIR/onos /tmp/chef-config"

scp -i "$KEY" -o StrictHostKeyChecking=no -r \
  "$SCRIPT_DIR/cookbooks/sdn_topology" \
  "ubuntu@$EC2_IP:/tmp/chef-cookbooks/sdn_topology"

scp -i "$KEY" -o StrictHostKeyChecking=no \
  "$ONOS_DIR/docker-compose.yml" \
  "$ONOS_DIR/start.sh" \
  "$ONOS_DIR/topology.py" \
  "ubuntu@$EC2_IP:/tmp/sdn-topology/$TOPOLOGY_DIR/onos/"

echo "==> Ensuring Chef is installed..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" \
  'command -v chef-solo &>/dev/null || curl -fsSL https://omnitruck.chef.io/install.sh | sudo bash'

echo "==> Writing Chef Solo config on remote..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" "bash -s $TOPOLOGY_DIR" << 'EOF'
set -e
TOPOLOGY_TYPE="${1:-fat-tree}"

cat > /tmp/chef-config/solo.rb << 'SOLORB'
cookbook_path "/tmp/chef-cookbooks"
data_collector.mode :off
SOLORB

cat > /tmp/chef-config/node.json << NODEJSON
{
  "sdn_topology": {
    "topology_type": "$TOPOLOGY_TYPE"
  },
  "run_list": ["recipe[sdn_topology]"]
}
NODEJSON

sudo chef-solo --chef-license accept -c /tmp/chef-config/solo.rb -j /tmp/chef-config/node.json
EOF

echo "==> Done. ONOS UI: http://$EC2_IP:8181/onos/ui"
