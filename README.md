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
