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
ONOS_DIR="$SCRIPT_DIR/../sdn-topology/fat-tree/onos"

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=30"

echo "==> Copying Puppet modules to $EC2_IP..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" "mkdir -p /tmp/puppet-modules /tmp/sdn-topology/fat-tree/onos"

scp -i "$KEY" -o StrictHostKeyChecking=no -r \
  "$SCRIPT_DIR/modules" \
  "ubuntu@$EC2_IP:/tmp/puppet-modules-src"

scp -i "$KEY" -o StrictHostKeyChecking=no \
  "$ONOS_DIR/docker-compose.yml" \
  "$ONOS_DIR/start.sh" \
  "$ONOS_DIR/topology.py" \
  "ubuntu@$EC2_IP:/tmp/sdn-topology/fat-tree/onos/"

scp -i "$KEY" -o StrictHostKeyChecking=no -r \
  "$SCRIPT_DIR/manifests" \
  "ubuntu@$EC2_IP:/tmp/puppet-manifests"

echo "==> Moving modules into place..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" "cp -r /tmp/puppet-modules-src/* /tmp/puppet-modules/ 2>/dev/null || cp -r /tmp/puppet-modules-src /tmp/puppet-modules/sdn_topology"

echo "==> Ensuring Puppet agent is installed..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" 'bash -s' << 'INSTALL'
if ! /opt/puppetlabs/bin/puppet --version &>/dev/null 2>&1; then
  wget -q https://apt.puppet.com/puppet8-release-noble.deb -O /tmp/puppet.deb
  sudo dpkg -i /tmp/puppet.deb
  sudo apt-get update -y
  sudo apt-get install -y puppet-agent
fi
INSTALL

echo "==> Applying Puppet configuration..."
ssh $SSH_OPTS "ubuntu@$EC2_IP" \
  "sudo /opt/puppetlabs/bin/puppet apply \
    /tmp/puppet-manifests/site.pp \
    --modulepath=/tmp/puppet-modules \
    --no-report"

echo "==> Done. ONOS UI: http://$EC2_IP:8181/onos/ui"
