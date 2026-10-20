# ☁️ AWS Cloud & DevOps Engineering Journey

[![CI](https://github.com/AdoMarna/aws-cloud-engineering-journey/actions/workflows/ci.yml/badge.svg)](https://github.com/AdoMarna/aws-cloud-engineering-journey/actions/workflows/ci.yml)

> **Hands-on Cloud Infrastructure, Automation & Zero-Trust Security.**  
> A high-intensity, project-driven journey building production-grade AWS infrastructure strictly via AWS CLI v2, Shell Scripting, and Infrastructure as Code.

---

## 🎯 Engineering Principles

This repository follows strict engineering and operational standards:

* **Zero-GUI / CLI-First:** 100% of the infrastructure is provisioned, managed, and destroyed via command-line tools (`aws-cli`, `jq`, `bash`, `make`).
* **Zero-Trust & Zero-SSH:** No long-lived credentials, no SSH (Port 22 closed), and zero direct Internet exposure for compute resources. Management is handled via **AWS STS** and **AWS SSM Session Manager**.
* **Idempotency & Resilience:** All deployment scripts use dynamic parsing (no hardcoded IDs) and strict Bash execution flags (`set -euo pipefail`).
* **Continuous Integration:** every push and pull request runs [`ci.yml`](./.github/workflows/ci.yml) — ShellCheck, Hadolint, `terraform fmt`/`validate`, TFLint, Checkov (each skipped rule justified in [`.checkov.yaml`](./.checkov.yaml)) and a Trivy scan of every container image. Actions are pinned by commit SHA, binaries by SHA-256.
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
| **[`proj00_iam_baseline`](./proj00_iam_baseline)** | Identity & Security | RBAC, Least Privilege, Temporary Credentials via STS, CLI Automation | ✅ Done |
| **[`proj01_custom_vpc`](./proj01_custom_vpc)** | Network Engineering | Custom Multi-AZ VPC, Public/Private/Isolated Subnets, NAT GW, NACLs | ✅ Done |
| **[`proj02_secure_compute`](./proj02_secure_compute)** | Compute & Hardening | Private EC2, Zero-SSH (SSM Manager), IMDSv2, KMS Parameter Store Injection | ✅ Done |
| **[`proj03_ha_auto_scaling`](./proj03_ha_auto_scaling)** | High Availability | Application Load Balancer (ALB), Auto Scaling Groups (ASG), Self-Healing | ✅ Done |
| **[`proj04_container_orchestration`](./proj04_container_orchestration)** | Containers | Docker, ECR, ECS Fargate Microservices, ALB Path-Based Routing, Autoscaling | ✅ Done |
| **[`proj05_terraform_iac`](./proj05_terraform_iac)** | IaC & State | Terraform Modular Architecture, Remote State S3 + DynamoDB Locking, Workspaces | ✅ Done |
| **[`proj06_serverless_event_driven`](./proj06_serverless_event_driven)** | Serverless | API Gateway, AWS Lambda, DynamoDB, SQS + DLQ (partial batch failures), EventBridge, dev/prod Workspaces | ✅ Done |

### Project Dependency Map

```text
  AWS CLI v2 + Bash (deploy in order)          Terraform (independent stacks)
 ┌──────────────────────────────────────┐    ┌──────────────────────────────────────┐
 │ proj00  IAM baseline (account-wide)  │    │ proj05  VPC + ALB + ECS Fargate      │
 │                                      │    │   backend: S3 + DynamoDB lock        │
 │ proj01  VPC (multi-AZ, 2× NAT GW)    │    │   (own scripts/bootstrap_backend.sh) │
 │   │  consumed by tag lookup          │    │                                      │
 │   ├──► proj02  private EC2 + SSM     │    │ proj06  API GW + Lambda + SQS +      │
 │   ├──► proj03  ALB + ASG (EC2)       │    │         DynamoDB + EventBridge       │
 │   └──► proj04  ALB + ECS Fargate     │    │   backend: S3 native lockfile        │
 │                + ECR                 │    │   (bootstrap/bootstrap.sh)           │
 └──────────────────────────────────────┘    │   dev/prod via Terraform Workspaces  │
                                             └──────────────────────────────────────┘
```

---

## 💸 FinOps — Estimated Running Cost

Order-of-magnitude **on-demand** cost while a stack is up in `eu-west-3`
(Paris), Free Tier excluded. Figures are indicative — check the
[AWS Pricing Calculator](https://calculator.aws/) before relying on them.
Every stack is meant to live for a work session, then be destroyed with
`make clean`.

| Project | Main billable resources | ≈ Cost / hour | ≈ If left running 30 days |
| :--- | :--- | :---: | :---: |
| `proj00` | IAM users, groups, roles, policies | $0.00 | $0 |
| `proj01` | 2× NAT Gateway + 2× Elastic IP (S3 Gateway Endpoint is free) | ~$0.10 | ~$75 |
| `proj02` | `proj01` + 2× `t3.micro` | ~$0.13 | ~$95 |
| `proj03` | `proj01` + ALB + 2–4× `t3.micro` (ASG) | ~$0.15–0.18 | ~$110–130 |
| `proj04` | `proj01` + ALB + 4–12 Fargate tasks (0.25 vCPU / 0.5 GiB) + ECR | ~$0.19–0.30 | ~$140–220 |
| `proj05` | Own VPC with 2× NAT Gateway + ALB + 2 Fargate tasks | ~$0.17 | ~$125 |
| `proj06` | Serverless, pay-per-request (API GW, Lambda, SQS, DynamoDB on-demand) | ~$0.00 idle | < $1 at lab traffic |

> **Takeaway:** NAT Gateways are the dominant idle cost of this repo — not
> compute. That is why every networked stack ships with an ordered `make clean`
> teardown that waits for NAT deletion, and why `proj06` was designed
> serverless-first.

---

## 🚀 Quickstart & Workflow Example

All projects are fully orchestrated via `Makefile` interfaces, but the
target names differ between the two project families in this repo:

* **`proj00`–`proj04`** are pure AWS CLI v2 + Bash, idempotent by design:

  ```bash
  git clone https://github.com/AdoMarna/aws-cloud-engineering-journey.git
  cd aws-cloud-engineering-journey/proj02_secure_compute

  make deploy   # Deploy the full stack
  make check    # Run project-specific health checks
  make clean    # Teardown all resources (FinOps zero-leak check)
  ```

* **`proj05`–`proj06`** are Terraform-driven, with a remote S3 backend
  bootstrapped once via `make bootstrap` (`proj05`:
  [`scripts/bootstrap_backend.sh`](./proj05_terraform_iac/scripts/bootstrap_backend.sh),
  `proj06`: [`bootstrap/bootstrap.sh`](./bootstrap/bootstrap.sh)):

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