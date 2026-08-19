#!/bin/bash
#
# architecture.sh — Visual map of the AWS architecture built across
# proj00_iam_baseline, proj01_custom_vpc, proj02_secure_compute and
# proj03_ha_auto_scaling.
#
# This is a STATIC diagram derived from reading the deploy/*.sh scripts in
# each project — it does not call the AWS CLI and does not require any
# resource to actually be deployed. Run it any time to get the big picture.
#
# Usage: bash architecture.sh [--no-color]

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled automatically when stdout is not a terminal, or with
# NO_COLOR=1 / --no-color)
# ---------------------------------------------------------------------------
use_color=1
for arg in "$@"; do
	[[ "$arg" == "--no-color" ]] && use_color=0
done
[[ -t 1 ]] || use_color=0
[[ -n "${NO_COLOR:-}" ]] && use_color=0

if [[ "$use_color" -eq 1 ]]; then
	RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
	RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
	BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; WHITE=$'\033[97m'
else
	RESET=""; BOLD=""; DIM=""
	RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""
fi

C_TITLE="${BOLD}${WHITE}"
C_VPC="${BOLD}${CYAN}"
C_PUBLIC="${GREEN}"
C_PRIVATE="${YELLOW}"
C_ISOLATED="${RED}"
C_SG="${MAGENTA}"
C_FLOW="${DIM}${WHITE}"
C_LABEL="${BOLD}${BLUE}"
C_DENY="${BOLD}${RED}"
C_ALLOW="${BOLD}${GREEN}"
C_IAM="${BOLD}${MAGENTA}"

# ---------------------------------------------------------------------------
# Drawing helpers — width is computed from the plain text, so boxes always
# line up regardless of ANSI codes.
# ---------------------------------------------------------------------------
BOX_WIDTH=78

hr() { printf '%s\n' "${DIM}$(printf '─%.0s' $(seq 1 "$BOX_WIDTH"))${RESET}"; }
hr_heavy() { printf '%s\n' "${BOLD}${WHITE}$(printf '═%.0s' $(seq 1 "$BOX_WIDTH"))${RESET}"; }

# section_box <color> <title>: draws a top/bottom-ruled header box sized to
# BOX_WIDTH regardless of the color codes wrapped around the title.
section_box() {
	local color="$1" title="$2"
	local inner=$((BOX_WIDTH - 2))
	local pad=$((inner - 2 - ${#title}))
	((pad < 0)) && pad=0
	printf '%s┌%s┐%s\n' "$color" "$(printf '─%.0s' $(seq 1 "$inner"))" "$RESET"
	printf '%s│ %s%*s │%s\n' "$color" "$title" "$pad" "" "$RESET"
	printf '%s└%s┘%s\n' "$color" "$(printf '─%.0s' $(seq 1 "$inner"))" "$RESET"
}

blank() { printf '\n'; }

cat <<EOF
${C_TITLE}   AWS Cloud Engineering Journey — Architecture Map${RESET}
${C_FLOW}   proj00 (IAM) -> proj01 (VPC) -> proj02 (Compute) -> proj03 (HA / Auto Scaling)${RESET}
EOF
hr_heavy
blank

# ---------------------------------------------------------------------------
# 0. IAM baseline (transversal — used to deploy/operate everything below)
# ---------------------------------------------------------------------------
section_box "$C_IAM" "proj00_iam_baseline — Identity & Access (account-wide, not VPC-scoped)"
blank
cat <<EOF
  ${C_IAM}IAM${RESET}  Developers-Group ──attached policy──> dev_restricted_policy
                             │                    (read-only EC2/S3/CloudWatch,
                             │                     explicit deny on VPC/IGW/IAM-user mgmt)
                             ├──attached policy──> enforce_mfa_policy (deny-all until MFA)
                             │
                             └──member──────────> dev-user-01  (CLI keys, profile: aws-dev-profile)

  ${C_IAM}Role${RESET} EmergencyAdminRole  <──sts:AssumeRole── dev-user-01
                             (1h temporary elevated credentials, used by
                              setup_iam.sh / assume_admin_role.sh)

  ${C_IAM}Role${RESET} EC2-SSM-Core-Role + EC2-SSM-Instance-Profile   ${C_FLOW}(built in proj02, reused by proj03)${RESET}
       ├─ policy: AmazonSSMManagedInstanceCore   (Session Manager, zero SSH)
       ├─ policy: CloudWatchAgentServerPolicy
       └─ inline:  ssm:GetParameter + kms:Decrypt, scoped to /config/app/* params only
EOF
blank
hr
blank

# ---------------------------------------------------------------------------
# 1. VPC network layout (proj01)
# ---------------------------------------------------------------------------
section_box "$C_VPC" "proj01_custom_vpc — MyVpc  (CIDR 10.0.0.0/16)  — eu-west-3"
blank
cat <<EOF
                                     ${C_FLOW}Internet${RESET}
                                        │
                                  ${BOLD}${WHITE}[ Internet Gateway ]${RESET}
                                        │
         ┌──────────────────────────────┴───────────────────────────────┐
         │                                                               │
${BOLD}   AZ1 (eu-west-3a)${RESET}                                        ${BOLD}AZ2 (eu-west-3b)${RESET}

${C_PUBLIC}   ┌─────── Public-Subnet-AZ1 ────────┐      ┌─────── Public-Subnet-AZ2 ────────┐
   │ 10.0.1.0/24                      │      │ 10.0.2.0/24                      │
   │ [ NAT Gateway #1 ] <- 1st EIP    │      │ [ NAT Gateway #2 ] <- 2nd EIP    │
   │ [ ALB nodes ]     (proj03)       │      │ [ ALB nodes ]     (proj03)       │
   └────────────────┬─────────────────┘      └────────────────┬─────────────────┘${RESET}
     Public Route Table                          Public Route Table
     0.0.0.0/0 → IGW                              0.0.0.0/0 → IGW
              │                                             │
              ▼                                             ▼
${C_PRIVATE}   ┌─────── Private-Subnet-AZ1 ───────┐      ┌─────── Private-Subnet-AZ2 ───────┐
   │ 10.0.10.0/24                     │      │ 10.0.20.0/24                     │
   │ [ my_instance_one ] (proj02)     │      │ [ my_instance_two ] (proj02)     │
   │ [ ASG app nodes ]   (proj03)     │      │ [ ASG app nodes ]   (proj03)     │
   └────────────────┬─────────────────┘      └────────────────┬─────────────────┘${RESET}
     Private-RT-AZ1                              Private-RT-AZ2
     0.0.0.0/0 → NAT GW #1                        0.0.0.0/0 → NAT GW #2
     + S3 Gateway VPC Endpoint                     + S3 Gateway VPC Endpoint
     (S3 traffic bypasses NAT)                      (S3 traffic bypasses NAT)
              │                                             │
              ▼                                             ▼
${C_ISOLATED}   ┌────── Isolated-Subnet-AZ1 ───────┐      ┌────── Isolated-Subnet-AZ2 ───────┐
   │ 10.0.100.0/24                    │      │ 10.0.200.0/24                    │
   │ (reserved - DB layer,            │      │ (reserved - DB layer,            │
   │  no compute deployed yet)        │      │  no compute deployed yet)        │
   └────────────────┬─────────────────┘      └────────────────┬─────────────────┘${RESET}
     Isolated Route Table                        Isolated Route Table
     ${C_DENY}NO route to 0.0.0.0/0${RESET}                        ${C_DENY}NO route to 0.0.0.0/0${RESET}
     (local VPC traffic only — enforced twice: no IGW/NAT route, AND custom NACL below)

  ${C_LABEL}Custom NACL — MyNaclCustom${RESET}  ${C_FLOW}(attached to both Isolated subnets, replaces default NACL)${RESET}
    ${C_ALLOW}✓ allow${RESET} all traffic  ⇄  10.0.10.0/24 (Private-AZ1)
    ${C_ALLOW}✓ allow${RESET} all traffic  ⇄  10.0.20.0/24 (Private-AZ2)
    ${C_DENY}✗ deny ${RESET} everything else, including 0.0.0.0/0 (Internet)
EOF
blank
hr
blank

# ---------------------------------------------------------------------------
# 2. Security Groups — stateful traffic chain
# ---------------------------------------------------------------------------
section_box "$C_SG" "Security Groups — stateful chain (referenced by SG-id, never by IP)"
blank
cat <<EOF
  ${C_FLOW}Internet (0.0.0.0/0)${RESET}
        │  ${C_ALLOW}80, 443/tcp${RESET}
        ▼
  ${C_SG}${BOLD}[ SG-ALB ]${RESET}  "public HTTP/HTTPS traffic to ALB"
        │  ${C_ALLOW}80, 443/tcp   (source = SG-ALB, not a CIDR)${RESET}
        ▼
  ${C_SG}${BOLD}[ SG-App ]${RESET}  "traffic from SG-ALB to application"   ${C_FLOW}(EC2 instances / ASG nodes)${RESET}
        │  ${C_ALLOW}5432/tcp      (source = SG-App, not a CIDR)${RESET}
        ▼
  ${C_SG}${BOLD}[ SG-DB ]${RESET}   "traffic from SG-App to database"      ${C_FLOW}(reserved, isolated subnets)${RESET}

  ${C_DENY}✗${RESET} Internet → SG-App directly       — blocked, must transit the ALB
  ${C_DENY}✗${RESET} Internet → SG-DB directly         — blocked under all circumstances
  ${C_DENY}✗${RESET} anything not explicitly listed    — security groups deny by default

  ${C_FLOW}proj02 also opens its own instance SG: ingress 80/tcp from 10.0.0.0/16 (VPC-wide),
  used by the two standalone SSM-managed nodes, independent of the ALB chain.${RESET}
EOF
blank
hr
blank

# ---------------------------------------------------------------------------
# 3. Compute — proj02 (static nodes) vs proj03 (HA / Auto Scaling)
# ---------------------------------------------------------------------------
section_box "${BOLD}${WHITE}" "Compute layer"
blank
cat <<EOF
  ${BOLD}proj02_secure_compute${RESET}  ${C_FLOW}— fixed, 2 nodes, zero-SSH via SSM${RESET}
  ┌────────────────────────────────────────────────────────────────────────┐
  │ my_instance_one  (Private-Subnet-AZ1)  --+                             │
  │ my_instance_two  (Private-Subnet-AZ2)  --+-- EC2-SSM-Instance-Profile  │
  │   AMI: al2023 (SSM resolve alias)   IMDSv2 required, hop-limit 2       │
  │   Access: AWS Systems Manager Session Manager only (no key pair)       │
  │   Config: SSM Parameter Store (/config/app/*, KMS-decrypted)           │
  └────────────────────────────────────────────────────────────────────────┘

  ${BOLD}proj03_ha_auto_scaling${RESET}  ${C_FLOW}— elastic, load-balanced, self-healing${RESET}
  ┌────────────────────────────────────────────────────────────────────────┐
  │ ${C_FLOW}Internet${RESET}                                                                │
  │    │                                                                    │
  │    ▼                                                                    │
  │ ${BOLD}${GREEN}[ my-load-balancer ]${RESET}  ALB, internet-facing                              │
  │    subnets: Public-Subnet-AZ1 + AZ2      sg: SG-ALB                    │
  │    listener: HTTP:80 ──forward──> target group                         │
  │    │                                                                    │
  │    ▼                                                                    │
  │ ${BOLD}${GREEN}[ my-tg ]${RESET}  Target Group (instance targets, health check "/")           │
  │    │                                                                    │
  │    ▼                                                                    │
  │ ${BOLD}${GREEN}[ my_asg ]${RESET}  Auto Scaling Group   min=2  desired=2  max=4               │
  │    subnets: Private-Subnet-AZ1 + AZ2     launch template: my_lt        │
  │    sg on instances: SG-ALB + SG-App                                    │
  │    health check: ELB, 600s grace period                                │
  │    scaling policy: TargetTracking @ ASGAverageCPUUtilization = 50%     │
  │      ├── [ EC2 ] ──┐                                                   │
  │      ├── [ EC2 ] ──┼── self-healing: unhealthy instance is             │
  │      └── [ .. ] ──┘    terminated & replaced automatically             │
  └────────────────────────────────────────────────────────────────────────┘
EOF
blank
hr
blank

# ---------------------------------------------------------------------------
# 4. Legend
# ---------------------------------------------------------------------------
cat <<EOF
${C_LABEL}Legend${RESET}
  ${C_PUBLIC}■${RESET} Public subnet (route → IGW)      ${C_PRIVATE}■${RESET} Private subnet (route → NAT GW)      ${C_ISOLATED}■${RESET} Isolated subnet (no internet route)
  ${C_SG}■${RESET} Security Group                    ${C_IAM}■${RESET} IAM identity / role                  ${C_ALLOW}✓${RESET} allowed   ${C_DENY}✗${RESET} denied

${DIM}Static diagram generated by reading deploy_vpc.sh, apply_network_security.sh,
deploy_compute.sh and deploy_ha_stack.sh — not a live AWS query. Re-run after
changing those scripts to keep this in sync. Use --no-color for plain output.${RESET}
EOF
