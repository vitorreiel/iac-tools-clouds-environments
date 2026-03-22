#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
KEY="$SCRIPT_DIR/ssh/chaves-aws.pem"

# ------------------------------------------------------------------
# Menu
# ------------------------------------------------------------------
echo "================================"
echo "  SDN Topology — IaC Benchmark"
echo "================================"
echo ""
echo "Select the IaC tool:"
echo "  1) Terraform"
echo "  2) OpenTofu"
echo "  3) CloudFormation"
echo "  4) Pulumi"
echo "  5) Ansible"
echo "  6) Puppet"
echo "  7) Chef"
echo ""
read -rp "Tool [1-7]: " TOOL_NUM
echo ""
read -rp "Number of repetitions: " REPEATS
echo ""

case "$TOOL_NUM" in
  1) TOOL_NAME="Terraform" ;;
  2) TOOL_NAME="OpenTofu" ;;
  3) TOOL_NAME="CloudFormation" ;;
  4) TOOL_NAME="Pulumi" ;;
  5) TOOL_NAME="Ansible" ;;
  6) TOOL_NAME="Puppet" ;;
  7) TOOL_NAME="Chef" ;;
  *) echo "Invalid option: $TOOL_NUM"; exit 1 ;;
esac

TOOL_DIR=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')
LOG_DIR="$SCRIPT_DIR/results/$TOOL_DIR"
LOG_FILE="$LOG_DIR/results.csv"

echo "Tool:        $TOOL_NAME"
echo "Repetitions: $REPEATS"
echo ""
read -rp "Confirm? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Initialize CSV log
mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "tool,iteration,duration_total_sec,duration_install_sec,duration_topology_sec,cpu_min_pct,cpu_max_pct,cpu_avg_pct,mem_min_pct,mem_max_pct,mem_avg_pct" > "$LOG_FILE"
fi

# ------------------------------------------------------------------
# Helper: wait for SSH
# ------------------------------------------------------------------
wait_ssh() {
  local ip="$1"
  echo "  Waiting for SSH on $ip..."
  for i in $(seq 1 30); do
    if ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
         -o BatchMode=yes "ubuntu@$ip" true 2>/dev/null; then
      echo "  SSH ready."
      return 0
    fi
    sleep 10
  done
  echo "  ERROR: SSH not available after 5 minutes."
  exit 1
}

# ------------------------------------------------------------------
# Helper: wait for cloud-init to finish (ensures apt is free)
# ------------------------------------------------------------------
wait_cloudinit() {
  local ip="$1"
  echo "  Waiting for cloud-init to complete..."
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 \
      -o BatchMode=yes "ubuntu@$ip" "sudo cloud-init status --wait" 2>/dev/null
  echo "  Cloud-init complete."
}

# ------------------------------------------------------------------
# Helper: install the tool's agent on the remote host (not timed)
# ------------------------------------------------------------------
prepare_tool() {
  local ip="$1"
  case "$TOOL_NUM" in
    6) # Puppet — install agent before timed run
      echo "  Installing Puppet agent (not timed)..."
      ssh -i "$KEY" -o StrictHostKeyChecking=no "ubuntu@$ip" 'bash -s' << 'INSTALL'
if ! /opt/puppetlabs/bin/puppet --version &>/dev/null 2>&1; then
  wget -q https://apt.puppet.com/puppet8-release-noble.deb -O /tmp/puppet.deb
  sudo dpkg -i /tmp/puppet.deb
  sudo apt-get update -y
  sudo apt-get install -y puppet-agent
fi
INSTALL
      ;;
    7) # Chef — install chef-solo before timed run
      echo "  Installing Chef (not timed)..."
      ssh -i "$KEY" -o StrictHostKeyChecking=no "ubuntu@$ip" \
        'command -v chef-solo &>/dev/null || curl -fsSL https://omnitruck.chef.io/install.sh | sudo bash'
      ;;
  esac
}

# ------------------------------------------------------------------
# Configure with the selected tool (this is what gets timed)
# ------------------------------------------------------------------
run_tool() {
  local ip="$1"
  local instance_id="$2"

  case "$TOOL_NUM" in

    1) # Terraform
      cd "$SCRIPT_DIR/terraform"
      terraform init -input=false -no-color
      terraform apply -auto-approve -input=false -no-color \
        -var="ec2_public_ip=$ip"
      ;;

    2) # OpenTofu
      cd "$SCRIPT_DIR/opentofu"
      tofu init -input=false -no-color
      tofu apply -auto-approve -input=false -no-color \
        -var="ec2_public_ip=$ip"
      ;;

    3) # CloudFormation
      cd "$SCRIPT_DIR/cloudformation"
      ./build.sh
      export AWS_ACCESS_KEY_ID=$(grep aws_access_key "$SCRIPT_DIR/template/terraform.tfvars" | awk -F'"' '{print $2}')
      export AWS_SECRET_ACCESS_KEY=$(grep aws_secret_key "$SCRIPT_DIR/template/terraform.tfvars" | awk -F'"' '{print $2}')
      export AWS_DEFAULT_REGION=$(grep aws_region "$SCRIPT_DIR/template/terraform.tfvars" | awk -F'"' '{print $2}')
      aws cloudformation deploy \
        --region us-east-2 \
        --template-file template.yaml \
        --stack-name sdn-topology-cfg \
        --parameter-overrides InstanceId="$instance_id" \
        --no-fail-on-empty-changeset

      # Poll SSM association until it finishes
      ASSOC_ID=$(aws cloudformation describe-stack-resource \
        --region us-east-2 \
        --stack-name sdn-topology-cfg \
        --logical-resource-id SDNTopologyAssociation \
        --query 'StackResourceDetail.PhysicalResourceId' \
        --output text)

      echo "  Waiting for SSM Run Command (association: $ASSOC_ID)..."
      while true; do
        STATUS=$(aws ssm describe-association-executions \
          --region us-east-2 \
          --association-id "$ASSOC_ID" \
          --query 'AssociationExecutions[0].Status' \
          --output text 2>/dev/null || echo "Pending")
        case "$STATUS" in
          Success) echo "  SSM completed successfully."; break ;;
          Failed)  echo "  ERROR: SSM Run Command failed."; exit 1 ;;
          *)       sleep 5 ;;
        esac
      done
      ;;
 
    4) # Pulumi
      cd "$SCRIPT_DIR/pulumi"
      export PULUMI_ACCESS_TOKEN=$(grep pulumi_access_token "$SCRIPT_DIR/template/terraform.tfvars" | awk -F'"' '{print $2}')
      python3 -m venv .venv 2>/dev/null || { sudo apt-get install -y python3-venv && python3 -m venv .venv; }
      .venv/bin/pip install -q -r requirements.txt
      PULUMI_PYTHON_CMD="$SCRIPT_DIR/pulumi/.venv/bin/python3" \
        pulumi stack select --create dev 2>/dev/null || true
      PULUMI_PYTHON_CMD="$SCRIPT_DIR/pulumi/.venv/bin/python3" \
        pulumi config set ec2PublicIp "$ip"
      PULUMI_PYTHON_CMD="$SCRIPT_DIR/pulumi/.venv/bin/python3" \
        pulumi up --yes --non-interactive --stack dev
      ;;

    5) # Ansible
      cd "$SCRIPT_DIR/ansible"
      ansible-playbook playbook.yml \
        -i "$ip," \
        -u ubuntu \
        --private-key "$KEY" \
        --ssh-extra-args="-o StrictHostKeyChecking=no"
      ;;

    6) # Puppet
      cd "$SCRIPT_DIR/puppet"
      ./deploy.sh "$ip"
      ;;

    7) # Chef
      cd "$SCRIPT_DIR/chef"
      ./deploy.sh "$ip"
      ;;

  esac
}

# ------------------------------------------------------------------
# Cleanup CloudFormation stack between iterations
# ------------------------------------------------------------------
cleanup_cloudformation() {
  if aws cloudformation describe-stacks --stack-name sdn-topology-cfg \
       --query 'Stacks[0].StackStatus' --output text 2>/dev/null | grep -qv "does not exist"; then
    echo "  Deleting CloudFormation stack..."
    aws cloudformation delete-stack --stack-name sdn-topology-cfg
    aws cloudformation wait stack-delete-complete --stack-name sdn-topology-cfg
  fi
}

# ------------------------------------------------------------------
# Main loop
# ------------------------------------------------------------------
for i in $(seq 1 "$REPEATS"); do
  echo ""
  echo "======================================================"
  echo "  Iteration $i / $REPEATS  —  $TOOL_NAME"
  echo "======================================================"

  # 1. Create instance
  echo ""
  echo "[1/3] Creating EC2 instance (template/)..."
  cd "$TEMPLATE_DIR"
  terraform init -input=false -no-color
  terraform apply -auto-approve -input=false -no-color

  EC2_IP=$(terraform output -raw public_ip)
  EC2_ID=$(terraform output -raw instance_id)
  echo "  Instance: $EC2_ID  IP: $EC2_IP"

  # 2. Wait for SSH + cloud-init, pre-install agent if needed, then run tool
  echo ""
  echo "[2/3] Configuring with $TOOL_NAME..."
  wait_ssh "$EC2_IP"
  wait_cloudinit "$EC2_IP"
  prepare_tool "$EC2_IP"

  # --- Timed execution ---

  # Start background CPU/RAM monitoring on the EC2 instance (1 sample/sec)
  echo "  Starting metrics monitoring..."
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes "ubuntu@$EC2_IP" 'bash -s' << 'MONITOR_SETUP'
rm -f /tmp/metrics.log /tmp/monitor.pid
cat > /tmp/monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
prev=( $(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat) )
while true; do
  sleep 1
  curr=( $(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat) )
  idle_diff=$(( ${curr[3]} - ${prev[3]} ))
  total_diff=0
  for i in 0 1 2 3 4 5 6; do total_diff=$(( total_diff + ${curr[$i]} - ${prev[$i]} )); done
  cpu=$(awk "BEGIN{printf \"%.1f\", ($total_diff>0)?(1-$idle_diff/$total_diff)*100:0}")
  mem=$(free | awk '/^Mem:/{printf "%.1f", $3/$2*100}')
  echo "$cpu $mem" >> /tmp/metrics.log
  prev=( "${curr[@]}" )
done
MONITOR_SCRIPT
chmod +x /tmp/monitor.sh
nohup bash /tmp/monitor.sh > /dev/null 2>&1 &
echo $! > /tmp/monitor.pid
MONITOR_SETUP

  T_START=$(date +%s%N)
  run_tool "$EC2_IP" "$EC2_ID"
  T_END=$(date +%s%N)

  # Stop monitoring
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    "ubuntu@$EC2_IP" 'kill $(cat /tmp/monitor.pid 2>/dev/null) 2>/dev/null; true'

  DURATION_TOTAL=$(echo "scale=3; ($T_END - $T_START) / 1000000000" | bc)

  # Read install-done timestamp written by the tool on the EC2 instance
  T_INSTALL=$(ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    "ubuntu@$EC2_IP" "cat /tmp/t_install_done" 2>/dev/null || echo "")

  if [ -n "$T_INSTALL" ]; then
    DURATION_INSTALL=$(echo "scale=3; ($T_INSTALL - $T_START) / 1000000000" | bc)
    # topology = total - install ensures the three values are always consistent
    DURATION_TOPOLOGY=$(echo "scale=3; $DURATION_TOTAL - $DURATION_INSTALL" | bc)
  else
    DURATION_INSTALL=""
    DURATION_TOPOLOGY=""
  fi

  # Collect CPU and RAM stats from the monitoring log
  METRICS=$(ssh -i "$KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    "ubuntu@$EC2_IP" \
    'awk "NR==1{cpu_min=\$1+0;cpu_max=\$1+0;mem_min=\$2+0;mem_max=\$2+0} \
    {cpu=\$1+0;mem=\$2+0; \
     cpu_sum+=cpu;mem_sum+=mem;n++; \
     if(cpu<cpu_min)cpu_min=cpu; if(cpu>cpu_max)cpu_max=cpu; \
     if(mem<mem_min)mem_min=mem; if(mem>mem_max)mem_max=mem} \
    END{if(n>0)printf \"%.1f %.1f %.1f %.1f %.1f %.1f\",cpu_min,cpu_max,cpu_sum/n,mem_min,mem_max,mem_sum/n}" \
    /tmp/metrics.log' 2>/dev/null || echo "")

  if [ -n "$METRICS" ]; then
    CPU_MIN=$(echo "$METRICS" | awk '{print $1}')
    CPU_MAX=$(echo "$METRICS" | awk '{print $2}')
    CPU_AVG=$(echo "$METRICS" | awk '{print $3}')
    MEM_MIN=$(echo "$METRICS" | awk '{print $4}')
    MEM_MAX=$(echo "$METRICS" | awk '{print $5}')
    MEM_AVG=$(echo "$METRICS" | awk '{print $6}')
  else
    CPU_MIN=""; CPU_MAX=""; CPU_AVG=""
    MEM_MIN=""; MEM_MAX=""; MEM_AVG=""
  fi

  echo "  Duration: total=${DURATION_TOTAL}s  install=${DURATION_INSTALL}s  topology=${DURATION_TOPOLOGY}s"
  echo "  CPU: min=${CPU_MIN}%  max=${CPU_MAX}%  avg=${CPU_AVG}%"
  echo "  RAM: min=${MEM_MIN}%  max=${MEM_MAX}%  avg=${MEM_AVG}%"
  echo "$TOOL_NAME,$i,$DURATION_TOTAL,$DURATION_INSTALL,$DURATION_TOPOLOGY,$CPU_MIN,$CPU_MAX,$CPU_AVG,$MEM_MIN,$MEM_MAX,$MEM_AVG" >> "$LOG_FILE"
  # -----------------------

  # 3. Cleanup and destroy
  echo ""
  echo "[3/3] Destroying EC2 instance..."
  [ "$TOOL_NUM" -eq 3 ] && cleanup_cloudformation
  cd "$TEMPLATE_DIR"
  terraform destroy -auto-approve -input=false -no-color

  echo "  Iteration $i complete."
done

echo ""
echo "======================================================"
echo "  All $REPEATS iteration(s) finished — $TOOL_NAME"
echo "  Results saved to: $LOG_FILE"
echo "======================================================"
