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
* **Compute & Orchestration:** EC2, Auto Scaling Groups (ASG), Launch Templates, Systems Manager (SSM)
* **Networking & Traffic:** VPC, Multi-AZ Subnetting, Route Tables, NAT Gateways, ALB (Application Load Balancer)
* **Identity & Security:** IAM (RBAC, AssumeRole via STS), KMS, Security Groups, NACLs, IMDSv2
* **Automation & Scripting:** Bash, GNU Make, AWS CLI v2, `jq`

---

## 🛣️ Roadmap & Project Status

| Project | Focus Area | Key Architectural Concepts | Status |
| :--- | :--- | :--- | :---: |
| **[`proj00_iam_baseline`](./proj00_iam_baseline)** | Identity & Security | RBAC, Least Privilege, Temporary Credentials via STS, CLI Automation | `125% Completed` |
| **[`proj01_custom_vpc`](./proj01_custom_vpc)** | Network Engineering | Custom Multi-AZ VPC, Public/Private/Isolated Subnets, NAT GW, NACLs | `125% Completed` |
| **[`proj02_secure_compute`](./proj02_secure_compute)** | Compute & Hardening | Private EC2, Zero-SSH (SSM Manager), IMDSv2, KMS Parameter Store Injection | `125% Completed` |
| **[`proj03_ha_auto_scaling`](./proj03_ha_auto_scaling)** | High Availability | Application Load Balancer (ALB), Auto Scaling Groups (ASG), Self-Healing | 🟡 *In Progress* |
| **`proj04_container_orchestration`** | Containers | Docker, ECR, AWS ECS Fargate / EKS Microservices Deployment | 🔴 *Planned* |
| **`proj05_infrastructure_as_code`** | IaC & State | Terraform Modular Architecture, Remote State S3/DynamoDB | 🔴 *Planned* |
| **`proj06_serverless_architecture`** | Serverless | API Gateway, AWS Lambda, DynamoDB, EventBridge Event-Driven Architecture | 🔴 *Planned* |

---

## 🚀 Quickstart & Workflow Example

All projects are fully orchestrated via `Makefile` interfaces. 

```bash
# Clone the repository
git clone https://github.com/<your-username>/aws-cloud-engineering-journey.git
cd aws-cloud-engineering-journey/proj02_secure_compute

# Deploy the full stack (see each project's README for prerequisites)
make deploy

# Run project-specific health checks
make check

# Teardown all resources (FinOps zero-leak check)
make clean
```

Each project directory ships its own `README.md` with the detailed
architecture, prerequisites, and full `make` target reference — start
there before running anything.

---

## 📂 Repository Conventions

* Every project is self-contained: its own `Makefile`, `scripts/`,
  `README.md`, and (when relevant) `templates/`/`configs/`.
* Every AWS resource is tagged `Project=<projXX>` + `Environment=dev`,
  used both for idempotent lookups and for `make clean` teardown —
  nothing is ever identified by a hardcoded ID.
* Later projects consume earlier ones by tag lookup (e.g. `proj02` reads
  `proj01`'s VPC/subnets) rather than duplicating infrastructure —
  deploy in numeric order.