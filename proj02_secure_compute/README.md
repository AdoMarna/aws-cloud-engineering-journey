# proj02_secure_compute — Compute Engine & Hardened Systems Management

Fully automated, idempotent provisioning of two hardened EC2 nodes with
**zero SSH and zero public IP**: private-subnet-only instances, remote
access exclusively through AWS Systems Manager Session Manager, IMDSv2
enforced, application secrets pulled from SSM Parameter Store at boot, and
automated patch compliance via SSM Patch Manager. No console clicks —
everything is built and torn down through `aws-cli v2` and `bash`.

## Architecture

```
                        Private-Subnet-AZ1          Private-Subnet-AZ2
                     ┌───────────────────────┐   ┌───────────────────────┐
                     │    my_instance_one     │   │    my_instance_two     │
                     │   nginx + CW Agent     │   │   nginx + CW Agent     │
                     │   IMDSv2 only, no      │   │   IMDSv2 only, no      │
                     │   public IP            │   │   public IP            │
                     └───────────┬───────────┘   └───────────┬───────────┘
                                 │        SG: TCP/80 from 10.0.0.0/16 only
                                 │               (no port 22, ever)
                                 └─────────────┬─────────────┘
                                               │
                          EC2-SSM-Core-Role (Instance Profile)
                                               │
              ┌────────────────────────────────┼────────────────────────────────┐
              │                                │                                │
      AmazonSSMManagedInstanceCore   CloudWatchAgentServerPolicy   Inline: read-only GetParameter
              │                                │                                │
      ┌───────▼────────┐              ┌────────▼────────┐             ┌─────────▼─────────┐
      │ Systems Manager │              │   CloudWatch     │             │  SSM Parameter     │
      │  (Session Mgr,  │              │   Agent metrics  │             │  Store             │
      │  Inventory,     │              │                  │             │  /config/app/env   │
      │  Patch Manager)  │              │                  │             │  /config/app/db_*  │
      └────────┬────────┘              └──────────────────┘             └────────────────────┘
               │
      Your terminal ── `aws ssm start-session` ──► encrypted session, no SSH, no public IP
```

Both instances live in the private subnets created by `proj01_custom_vpc`
(`Private-Subnet-AZ1` / `Private-Subnet-AZ2`) — this project provisions no
network of its own, it consumes proj01's VPC/subnets by tag lookup.

## Repository layout

```text
proj02_secure_compute/
├── Makefile
├── README.md
├── rules.txt
├── scripts/
│   ├── deploy_compute.sh
│   ├── connect_instance.sh
│   ├── check_nodes_health.sh
│   ├── inject_config.sh
│   └── cleanup_compute.sh
└── templates/
    ├── ssm_trust_policy.json
    └── userdata.sh
```

## Prerequisites

- `aws-cli v2`, `jq`, `bash`, `session-manager-plugin`.
- `proj01_custom_vpc` already deployed: this project looks up its VPC
  (`Project=proj01` tag) and both private subnets (`Private-Subnet-AZ1` /
  `Private-Subnet-AZ2`) by name — it does not create any network resources.
- IAM permissions to create roles, instance profiles, security groups, EC2
  instances, SSM parameters/associations/patch baselines (see
  `Projet 00 — AWS Identity & Security Baseline` for the IAM setup used
  here).

## Usage

```bash
make            # deploy the full stack (~5-10 minutes, incl. SSM registration)
make deploy     # same as above
make connect    # open an interactive SSM session on my_instance_one
make check      # run a Nginx health check on both nodes, prints a JSON report
make clean      # tear down every proj02 resource, then cascades into proj01 cleanup
make help       # list all targets
```

Every script is idempotent: running `make deploy` twice in a row never
creates duplicate resources. Each resource is looked up by its `Name` (or
association/baseline name) plus `Project=proj02` tag before anything is
created, so a script can be safely re-run after a partial failure.

## Design conventions

- Every script starts with `set -euo pipefail`.
- Every AWS-created resource carries a standardized `Name` tag plus
  `Project=proj02`, `Environment=dev`, used both for idempotency lookups
  and for cleanup.
- No hardcoded AMI: the AMI ID is resolved dynamically at every
  `run-instances` call via the official AWS SSM public parameter
  (`resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`),
  never written in the script.
- No hardcoded secret: `deploy_compute.sh` generates a random database
  password (`openssl rand -base64 18`) on every run and passes it to
  `inject_config.sh` through the `DB_PASSWORD` environment variable —
  never as a CLI argument (which would leak into `ps aux` / shell
  history), never committed to the repository.
- Each resource follows the same inline pattern: `describe`/`get` to check
  if it already exists, `if` to skip creation when it does, `create`
  otherwise.

## Scripts

### `scripts/deploy_compute.sh`

Provisions, in order:

1. `EC2-SSM-Core-Role` IAM role (trust policy in
   `templates/ssm_trust_policy.json`), with `AmazonSSMManagedInstanceCore`
   and `CloudWatchAgentServerPolicy` attached, plus an inline
   `SSM-Parameter-ReadOnly` policy scoped to the two application
   parameters and the default SSM KMS key.
2. `EC2-SSM-Instance-Profile`, with the role attached.
3. A Security Group allowing inbound TCP/80 from `10.0.0.0/16` only — no
   port 22 rule exists anywhere in this project.
4. `my_instance_one` (AZ1) and `my_instance_two` (AZ2): `t3.micro`, no
   public IP, IMDSv2 enforced (`HttpTokens=required`), bootstrapped by
   `templates/userdata.sh`.
5. `inject_config.sh`, to publish the application config to SSM Parameter
   Store before the instances need it.
6. Waits for both instances to register as SSM managed nodes
   (`ssm describe-instance-information` polling on `PingStatus=Online`).
7. A self-owned Patch Baseline (`proj02-al2023-baseline`, Amazon Linux
   2023, auto-approves Security/Bugfix patches of Critical/Important
   severity) registered against the `proj02-dev` Patch Group, an SSM
   Inventory association (software inventory every 30 min), and a Patch
   Manager scan association (daily) — both targeted by `Project=proj02`
   tag.
8. Triggers an immediate patch scan and prints the compliance report via
   `aws ssm describe-instance-patch-states`.

### `templates/userdata.sh`

Runs once at first boot: updates packages, installs and starts Nginx,
fetches instance metadata through **IMDSv2 only** (token-based), pulls
`/config/app/env` and `/config/app/db_password` from SSM Parameter Store,
and renders a status page showing hostname, instance ID, AZ, environment,
and a **masked** database password (`****` + last 4 characters only — the
full secret is never written to a world-readable file). Also installs and
starts the CloudWatch Agent.

### `scripts/connect_instance.sh`

Opens an interactive shell on `my_instance_one` via
`aws ssm start-session` — encrypted, audited, no SSH daemon, no public IP,
no open port 22.

### `scripts/check_nodes_health.sh`

Sends a single `systemctl status nginx` command to both instances
simultaneously via `aws ssm send-command`, waits for completion on each,
and prints a JSON array report (name, instance ID, status, stdout/stderr)
built with `jq`.

### `scripts/inject_config.sh`

Publishes `/config/app/env` (String) and `/config/app/db_password`
(SecureString, encrypted with the default `alias/aws/ssm` KMS key) to SSM
Parameter Store, tags them `Project`/`Environment`, and prompts for
confirmation before overwriting existing parameters (bypassed with
`FORCE=1`). Reads the password from the `DB_PASSWORD` environment
variable — never a CLI argument. Can be run standalone as long as
`deploy_compute.sh` has already created the IAM role and its inline
policy.

### `scripts/cleanup_compute.sh`

Tears down every resource created above, in dependency order: SSM
associations (Inventory, Patch scan) → Patch Group deregistration and
Patch Baseline deletion → instance termination (actively waited on via
`aws ec2 wait instance-terminated`) → instance profile → security group
(ingress rule revoked first) → SSM parameters → IAM role (policies
detached/deleted before the role itself). Prompts for confirmation unless
`FORCE=1`. Finishes by invoking proj01's `cleanup_vpc.sh`, cascading the
teardown down to the network layer.

## Security

- **Zero SSH, zero public IP**: enforced structurally — no port 22 rule
  exists in the Security Group, and no `--associate-public-ip-address` is
  ever passed to `run-instances`. All remote access goes through SSM
  Session Manager, which requires no inbound port at all.
- **IMDSv2 only**: `HttpTokens=required` on both instances blocks
  unauthenticated IMDSv1 requests, closing the classic SSRF-to-credentials
  path.
- No access key, secret, or Account ID is ever written in plaintext in the
  repository. The database password is generated at deploy time, passed
  through an environment variable (never a CLI argument or a file), and
  `unset` immediately after use in every script that touches it.
- The database password is displayed on the Nginx status page **masked**
  (last 4 characters only), to prove SSM Parameter Store retrieval works
  without exposing the full secret to anyone with network access to the
  instance.
