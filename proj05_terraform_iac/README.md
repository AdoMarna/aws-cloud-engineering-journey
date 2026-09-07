# proj05_terraform_iac — Enterprise Infrastructure as Code (Terraform & Remote State)

Fully automated, declarative, and modular provisioning of a production-ready, highly available AWS infrastructure using **Terraform (v1.5+)**. The stack replicates and refactors previous projects into clean, reusable HCL modules (VPC, Security Groups, ALB, ECS Fargate) with zero hardcoded values or manual GUI steps. State locking and encryption are strictly enforced via an Amazon S3 backend and a DynamoDB locking table. Operations are orchestrated through `make`, wrapper Bash scripts (`set -euo pipefail`), and Terraform Workspaces.

## Architecture

```text
                                  Internet traffic
                                         │
                                         ▼ (port 80)
                        ┌────────────────────────────────┐
                        │   Application Load Balancer    │
                        │   Public-Subnet-AZ1 / AZ2      │
                        │   SG-ALB: 80 from 0.0.0.0/0    │
                        └────────────┬───────────────────┘
                                     │ Listener :80
                        ┌────────────┴───────────────────┘
                        │ Path Routing / State Management
                        ▼
                Target Group (HTTP :8080)
                Health check: GET /
                        │
        ┌───────────────┴───────────────┐
        ▼                               ▼
Private-Subnet-AZ1              Private-Subnet-AZ2
┌─────────────────┐             ┌─────────────────┐
│ ECS Task        │             │ ECS Task        │
│ (Fargate)       │             │ (Fargate)       │
│ SG-App: 8080    │             │ SG-App: 8080    │
│ from SG-ALB     │             │ from SG-ALB     │
└─────────────────┘             └─────────────────┘
        Service ECS (Fargate) desired=2, min=2, max=6
        Cluster: proj05-cluster-${workspace}

```

State locking and remote storage management:

```text
┌─────────────────────────────────────────────────────────────────┐
│                   Terraform Remote Backend                      │
│                                                                 │
│  ┌─────────────────────────────┐   ┌─────────────────────────┐  │
│  │    Amazon S3 Bucket         │   │   Amazon DynamoDB       │  │
│  │  (Encrypted, Versioned)     │   │  (State LockID Table)   │  │
│  │   terraform.tfstate         │   │   LockID Key Lookup     │  │
│  └─────────────────────────────┘   └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

```

## Repository layout

```text
proj05_terraform_iac/
├── Makefile
├── README.md
├── main.tf                    # Root terraform module calls
├── variables.tf               # Global input variable declarations & type constraints
├── outputs.tf                 # Root outputs (ALB DNS, VPC ID, Workspace state)
├── backend.tf                 # S3 remote backend configuration with DynamoDB locking
├── terraform.tfvars.example   # Template variable values
├── modules/
│   ├── vpc/
│   │   ├── main.tf            # VPC, Subnets (Public/Private/Isolated), Route Tables, IGW, NAT GW
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/
│   │   ├── main.tf            # SG-ALB, SG-App, SG-DB with strict cross-referencing
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── compute/
│       ├── main.tf            # ECS Cluster, Fargate Task Def, ECS Service & ALB Target Group
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev.tfvars             # Development environment input values
│   └── prod.tfvars            # Production environment input values
└── scripts/
    ├── bootstrap_backend.sh   # Provisions S3 bucket & DynamoDB table for state storage
    ├── check_drift.sh         # Zero-drift detection via terraform plan -detailed-exitcode
    └── cleanup_terraform.sh   # Full destroy, S3 backend purge, and local state clean

```

## Prerequisites

* `terraform` (v1.5+), `aws-cli v2`, `jq`, `bash`.
* AWS CLI configured with valid administrator/provisioning permissions.
* Docker daemon running locally (if building container images for ECS compute).
* Security scanner installed (`trivy` or `checkov`) for static security analysis.

## Usage

```bash
make bootstrap   # Provision S3 bucket & DynamoDB table for Terraform remote state
make init        # Initialize Terraform backend and modules
make fmt         # Format HCL files across all modules
make validate    # Run syntax and type validation checks
make lint        # Run security scanning (trivy/checkov) on IaC code
make plan        # Run terraform plan using dev.tfvars
make apply       # Apply terraform plan to provision the full infrastructure
make drift       # Execute drift check script (returns exit code 0 if synced)
make clean       # Destroy all Terraform resources, purge S3 state bucket, and clean local workspace
make help        # Display target help

```

### Workspaces & Multiple Environments

```bash
# Switch to development environment
terraform workspace select -or-create=true dev
terraform plan -var-file="environments/dev.tfvars"

# Switch to production environment
terraform workspace select -or-create=true prod
terraform plan -var-file="environments/prod.tfvars"

```

### Verifying State & Deployment

```bash
# Verify ALB DNS from root output
alb_dns=$(terraform output -raw load_balancer_dns)

# Test load balancer endpoint
for i in $(seq 1 5); do curl -s "http://$alb_dns/" | jq -c .; done

# Execute Zero-Drift check script
./scripts/check_drift.sh

```

## Design conventions

* Every Shell script starts with `set -euo pipefail`.
* **Pure HCL / No CLI Creation**: 100% of the AWS infrastructure is declared in Terraform HCL files. No resource is created manually or via `aws-cli` outside the initial bootstrapping step.
* **Dynamic Naming via Workspaces**: Every resource carries standardized tags (`Project=proj05`, `Environment=${terraform.workspace}`) and includes `${terraform.workspace}` in its `Name` attribute.
* **Strict Module Encapsulation**: Root `main.tf` acts strictly as an orchestrator. Sub-modules (`vpc`, `security`, `compute`) maintain tight encapsulation with inputs defined in `variables.tf` and outputs in `outputs.tf`.
* **Security Group Chaining**: Rules use `security_group_id` references rather than CIDR ranges to ensure `SG-App` only accepts traffic originating from `SG-ALB`.
* **Remote State Locking**: State is stored in an S3 bucket with versioning and Server-Side Encryption (`AES256`) enabled, paired with DynamoDB state locking to block concurrent updates.

## Scripts

### `scripts/bootstrap_backend.sh`

1. Checks if the designated S3 state bucket and DynamoDB locking table already exist via `aws s3api` and `aws dynamodb`.
2. Creates the S3 bucket if missing, enables `versioning`, and configures default Server-Side Encryption (`AES256`).
3. Creates the DynamoDB table with primary key `LockID` (`STRING`) in `PAY_PER_REQUEST` billing mode if missing.
4. Prepares `backend.tf` for execution of `terraform init`.

### `scripts/check_drift.sh`

1. Runs `terraform plan -detailed-exitcode -var-file="environments/${WORKSPACE}.tfvars"`.
2. Inspects exit code:
* `0`: Succeeded, no changes needed (zero drift).
* `2`: Succeeded, infrastructure drift detected (changes required).
* `1`: Error encountered during planning.


3. Outputs state status and returns the appropriate system exit code.

### `scripts/cleanup_terraform.sh`

1. Runs `terraform destroy -auto-approve -var-file="environments/${WORKSPACE}.tfvars"` for active workspaces.
2. Empties all object versions and markers from the remote S3 state bucket.
3. Deletes the S3 backend bucket and DynamoDB state locking table.
4. Purges local `.terraform/` directories, `.terraform.lock.hcl`, and workspace state files.

## Security

* **No Direct Internet Exposure**: Compute resources (ECS Fargate tasks / EC2 instances) are deployed strictly in private subnets with no public IP address assignment.
* **State File Encryption**: `terraform.tfstate` is encrypted at rest using `AES256` on Amazon S3 and transferred securely over HTTPS.
* **Security Group Chaining**: Inbound rules on internal resources explicitly reference `SG-ALB` security group IDs rather than broad subnet IP ranges.
* **Static Security Analysis**: Automated linting rules (`trivy`/`checkov`) enforce checks against overly permissive CIDRs, unencrypted resources, or broad IAM policies prior to deployment.
* **Zero Hardcoded Secrets**: Credentials, AWS Account IDs, and sensitive tokens are injected exclusively via environment variables (`TF_VAR_*`) or secure secret stores—never stored in `.tf` files or committed to Git repositories.