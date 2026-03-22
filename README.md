# SDN Topology — IaC Provisioning

## Architecture

```
template/   ← creates the EC2 instance (run once, shared by all tools)
terraform/  ┐
opentofu/   │
cloudform/  ├─ configure the running instance (each tool independently)
pulumi/     │
ansible/    │
puppet/     │
chef/       ┘
```

All 7 tools configure the same instance: install Docker and deploy the ONOS fat-tree topology from `sdn-topology/fat-tree/onos/`.

## Instance specs

| Parameter  | Value                                     |
|------------|-------------------------------------------|
| Region     | us-east-1                                 |
| Type       | c7i-flex.large  ← change in `template/variables.tf` |
| OS         | Ubuntu 24.04 LTS (`ami-07062e2a343acc423`) |
| Storage    | 30 GB gp3                                 |
| Ports      | 22 (SSH), 6653 (OpenFlow), 8181 (ONOS UI) |

## Credentials

```bash
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_DEFAULT_REGION=us-east-1
```

---

## Step 1 — Create the EC2 instance (template/)

```bash
cd template
terraform init
terraform apply
# note the public_ip output
```

To change the instance type, edit `template/variables.tf` — the variable is at the top of the file.

---

## Step 2 — Configure the instance (choose one tool)

### Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# set ec2_public_ip in terraform.tfvars
terraform init
terraform apply
```

### OpenTofu

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars
# set ec2_public_ip in terraform.tfvars
tofu init
tofu apply
```

### CloudFormation

The instance must have the SSM agent running and an IAM instance profile with `AmazonSSMManagedInstanceCore`.

```bash
cd cloudformation
./build.sh          # generates template.yaml (embeds topology files)
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name sdn-topology \
  --parameter-overrides InstanceId=<instance-id>
```

### Pulumi

```bash
cd pulumi
pip install -r requirements.txt
pulumi stack init dev
pulumi config set ec2PublicIp <public-ip>
pulumi up
```

### Ansible

```bash
cd ansible
# edit inventory.ini — set EC2_PUBLIC_IP
ansible-playbook playbook.yml
```

### Puppet

```bash
cd puppet
./deploy.sh <EC2_PUBLIC_IP>
```

### Chef

```bash
cd chef
./deploy.sh <EC2_PUBLIC_IP>
```

---

## After configuration

- **ONOS UI**: `http://<EC2_PUBLIC_IP>:8181/onos/ui` (credentials: `onos` / `rocks`)
- **SSH**: `ssh -i ssh/chaves-aws.pem ubuntu@<EC2_PUBLIC_IP>`

## Benchmark — Metrics collected

Results are saved to `results/<tool>/results.csv` after each run of `start.sh`. Every row represents one iteration. The table below describes all 19 columns.

### Timing

| Column | Meaning | How it is captured |
|---|---|---|
| `duration_total_sec` | Total time from tool start until the environment is fully operational (`duration_install + duration_topology + convergence_sec`) | Computed as the sum of the three sub-phases. Reflects how long it takes for each tool to deliver a **ready-to-use** environment |
| `duration_install_sec` | Time spent installing resources (OVS kernel module, Docker, packages) | Each tool writes `date +%s%N > /tmp/t_install_done` on the EC2 instance right after `systemctl start docker`. `duration_install = (t_install_done − T_START) / 1e9` |
| `duration_topology_sec` | Time spent deploying the SDN topology (`docker compose up -d` and file staging) | Derived: `(T_END − T_START) / 1e9 − duration_install`. Measures the tool's topology phase, ending when `run_tool()` returns |
| `convergence_sec` | Additional time after the tool finishes until ONOS is fully operational | See Convergence section below. Placed next to the timing columns because it completes the `duration_total` breakdown |

### CPU (sampled every second on the EC2 instance during the full run)

| Column | Meaning | How it is captured |
|---|---|---|
| `cpu_min_pct` | Lowest CPU utilisation sample recorded | Background script (`/tmp/monitor.sh`) reads `/proc/stat` jiffies every second and computes `(1 − idle_delta / total_delta) × 100`. Min/max/avg are derived from `/tmp/metrics.log` via `awk` after the run |
| `cpu_max_pct` | Highest CPU utilisation sample recorded | Same as above |
| `cpu_avg_pct` | Average CPU utilisation across all samples | Same as above |

### RAM (sampled every second on the EC2 instance during the full run)

| Column | Meaning | How it is captured |
|---|---|---|
| `mem_min_pct` | Lowest RAM utilisation sample recorded | Same background script reads `free` every second and computes `used / total × 100` |
| `mem_max_pct` | Highest RAM utilisation sample recorded | Same as above |
| `mem_avg_pct` | Average RAM utilisation across all samples | Same as above |

### Network (measured on the EC2 instance)

| Column | Meaning | How it is captured |
|---|---|---|
| `net_rx_mb` | Total data downloaded during provisioning (apt packages, Docker images, etc.) | Delta of RX bytes from `/proc/net/dev` (all non-loopback interfaces), read immediately before `T_START` and after `T_END`, converted to MB |
| `net_tx_mb` | Total data uploaded during provisioning (manifests, playbooks, cookbooks copied to the instance) | Same, but TX bytes |
| `net_rx_rate_mbps` | Average download throughput | `net_rx_mb / duration_total_sec` |
| `net_tx_rate_mbps` | Average upload throughput | `net_tx_mb / duration_total_sec` |

### Disk I/O (measured on the EC2 instance)

| Column | Meaning | How it is captured |
|---|---|---|
| `disk_read_mb` | Total data read from disk during provisioning | Delta of sectors-read from `/proc/diskstats` (physical block devices only: `sda`, `nvme*n*`, `xvda`, etc.), read before and after the run; sectors × 512 B / 1 MiB |
| `disk_write_mb` | Total data written to disk during provisioning (package files, Docker layers, configuration files) | Same, but sectors-written |

### Convergence

| Column | Meaning | How it is captured |
|---|---|---|
| `convergence_sec` | Additional time after the tool finishes (`T_END`) until ONOS responds to `GET /onos/v1/info`. Included in `duration_total_sec` | Immediately after `T_END`, the local machine polls `http://<EC2>:8181/onos/v1/info` (credentials `onos:rocks`) every second until HTTP 200 is received. Maximum wait: 5 minutes |

### Operations

| Column | Meaning | How it is captured |
|---|---|---|
| `ops_count` | Number of resources/tasks declared and applied by the tool | `run_tool()` stdout is captured via `tee`. After the run, a per-tool parser extracts the count from the output (see table below) |

**Per-tool parsing for `ops_count`:**

| Tool | What is counted | Pattern matched |
|---|---|---|
| Terraform / OpenTofu | Sum of resources added + changed + destroyed | `Apply complete! Resources: X added, Y changed, Z destroyed.` |
| CloudFormation | Number of resources in the CloudFormation stack | `aws cloudformation describe-stack-resources … --query 'length(StackResources)'` |
| Pulumi | Number of resources created | `+ N created` in the Resources summary |
| Ansible | Number of tasks executed | `ok=N` in the play recap |
| Puppet | Number of resources applied | Count of `Notice: /Stage[main]/…` lines in the output |
| Chef | Number of resources updated | `N/M resources updated` in the final summary |

---

## How each tool references topology files

All tools read directly from `sdn-topology/fat-tree/onos/` — no duplication.

| Tool           | Mechanism                                                    |
|----------------|--------------------------------------------------------------|
| Terraform      | `file` + `remote-exec` provisioners via SSH                  |
| OpenTofu       | same as Terraform                                            |
| CloudFormation | `build.sh` embeds base64 content into SSM Run Command doc    |
| Pulumi         | `pulumi-command` `CopyToRemote` + `Command` via SSH          |
| Ansible        | `copy` module with `src` pointing to `sdn-topology/`         |
| Puppet         | `deploy.sh` copies modules + topology files, runs remotely   |
| Chef           | `deploy.sh` copies cookbook + topology files, runs chef-solo |
