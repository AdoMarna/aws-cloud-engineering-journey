# ☁️ AWS Cloud & DevOps Engineering Journey

> **Hands-on Cloud Infrastructure, Automation & Zero-Trust Security.**  
> A high-intensity, project-driven journey building production-grade AWS infrastructure strictly via AWS CLI v2, Shell Scripting, and Infrastructure as Code.

---

## 🎯 Engineering Principles

This repository follows strict engineering and operational standards:

* **Zero-GUI / CLI-First:** 100% of the infrastructure is provisioned, managed, and destroyed via command-line tools (`aws-cli`, `jq`, `bash`, `make`).
* **Zero-Trust & Zero-SSH:** No long-lived credentials, no SSH (Port 22 closed), and zero direct Internet exposure for compute resources. Management is handled via **AWS STS** and **AWS SSM Session Manager**.
* **Idempotency & Resilience:** All deployment scripts use dynamic parsing (no hardcoded IDs) and strict Bash execution flags (`set -euo pipefail`).
* **Strict FinOps:** Automated lifecycle teardown scripts (`make clean`) with strict state waiters ensuring an almost **$0.00 idle cost footprint**.

---

## 🛠️ Tech Stack & Tooling

* **Cloud Provider:** Amazon Web Services (AWS)
* **Compute & Orchestration:** EC2, Auto Scaling Groups (ASG), Launch Templates, Systems Manager (SSM), ECS Fargate
* **Serverless & Events:** API Gateway (HTTP API v2), AWS Lambda, DynamoDB, SQS + DLQ, EventBridge
* **Networking & Traffic:** VPC, Multi-AZ Subnetting, Route Tables, NAT Gateways, ALB (Application Load Balancer)
* **Identity & Security:** IAM (RBAC, AssumeRole via STS), KMS, Security Groups, NACLs, IMDSv2
* **Infrastructure as Code:** Terraform (modular architecture, S3 remote state, state locking, Workspaces)
* **Automation & Scripting:** Bash, GNU Make, AWS CLI v2, `jq`

---

## 🛣️ Roadmap & Project Status

| Project | Focus Area | Key Architectural Concepts | Status |
| :--- | :--- | :--- | :---: |
| **[`proj00_iam_baseline`](./proj00_iam_baseline)** | Identity & Security | RBAC, Least Privilege, Temporary Credentials via STS, CLI Automation | `125% Completed` |
| **[`proj01_custom_vpc`](./proj01_custom_vpc)** | Network Engineering | Custom Multi-AZ VPC, Public/Private/Isolated Subnets, NAT GW, NACLs | `125% Completed` |
| **[`proj02_secure_compute`](./proj02_secure_compute)** | Compute & Hardening | Private EC2, Zero-SSH (SSM Manager), IMDSv2, KMS Parameter Store Injection | `125% Completed` |
| **[`proj03_ha_auto_scaling`](./proj03_ha_auto_scaling)** | High Availability | Application Load Balancer (ALB), Auto Scaling Groups (ASG), Self-Healing | `125% Completed` |
| **[`proj04_container_orchestration`](./proj04_container_orchestration)** | Containers | Docker, ECR, ECS Fargate Microservices, ALB Path-Based Routing, Autoscaling | `125% Completed` |
| **[`proj05_terraform_iac`](./proj05_terraform_iac)** | IaC & State | Terraform Modular Architecture, Remote State S3 + DynamoDB Locking, Workspaces | `125% Completed` |
| **[`proj06_serverless_event_driven`](./proj06_serverless_event_driven)** | Serverless | API Gateway, AWS Lambda, DynamoDB, SQS + DLQ, EventBridge Event-Driven Pipeline | `125% Completed` |

---

## 🚀 Quickstart & Workflow Example

All projects are fully orchestrated via `Makefile` interfaces, but the
target names differ between the two project families in this repo:

* **`proj00`–`proj04`** are pure AWS CLI v2 + Bash, idempotent by design:

  ```bash
  git clone https://github.com/<your-username>/aws-cloud-engineering-journey.git
  cd aws-cloud-engineering-journey/proj02_secure_compute

  make deploy   # Deploy the full stack
  make check    # Run project-specific health checks
  make clean    # Teardown all resources (FinOps zero-leak check)
  ```

* **`proj05`–`proj06`** are Terraform-driven, with a remote S3 backend
  bootstrapped once via [`bootstrap/bootstrap.sh`](./bootstrap/bootstrap.sh):

  ```bash
  cd aws-cloud-engineering-journey/proj06_serverless_event_driven

  make bootstrap   # Provision the S3 remote state backend (once)
  make init        # terraform init
  make plan        # terraform plan (ENV=dev by default, ENV=prod supported)
  make apply       # terraform apply
  make test        # Run the project's end-to-end smoke test
  make clean       # terraform destroy + full resource cleanup
  ```

Each project directory ships its own `README.md` with the detailed
architecture, prerequisites, and full `make` target reference — start
there before running anything.

---

## 📂 Repository Conventions

* Every project is self-contained: its own `Makefile`, `scripts/`,
  `README.md`, and (when relevant) `templates/`/`configs/`.
* Every AWS resource is tagged `Project=<projXX>` + `Environment=<dev|prod>`,
  used both for idempotent lookups and for `make clean` teardown —
  nothing is ever identified by a hardcoded ID.
* No hardcoded AWS region: CLI/Bash projects read `${AWS_REGION:-eu-west-3}`,
  Terraform projects expose a `var.aws_region` (default `eu-west-3`) — override
  either to redeploy into a different region.
* **`proj00`–`proj04`** (CLI/Bash): later projects consume earlier ones by tag
  lookup (e.g. `proj02` reads `proj01`'s VPC/subnets) rather than duplicating
  infrastructure — deploy in numeric order.
* **`proj05`–`proj06`** (Terraform): each project is a fully independent,
  modular stack with its own S3 remote state backend and state locking — no
  cross-project tag lookups; state locking cannot use a variable region since
  Terraform evaluates `backend` blocks before variables are resolved.