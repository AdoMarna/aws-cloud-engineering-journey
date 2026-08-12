# proj01_custom_vpc — Custom Multi-AZ VPC Architecture

Fully automated, idempotent AWS network provisioning: a custom VPC spread
across two Availability Zones with public, private, and isolated subnet
tiers, highly-available NAT, a two-layer security model (Security Groups +
NACL), and a zero-cost S3 VPC Endpoint. No console clicks — everything is
built and torn down through `aws-cli v2` and `bash`.

## Architecture

```
                                Internet
                                   │
                          ┌────────▼────────┐
                          │ Internet Gateway │
                          └────────┬────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │      Public Route Table       │
                    └───────┬───────────────┬───────┘
              ┌─────────────▼───┐     ┌─────▼─────────────┐
              │ Public-Subnet-AZ1│     │ Public-Subnet-AZ2  │
              │  10.0.1.0/24     │     │  10.0.2.0/24       │
              │  [NAT GW 1] [ALB]│     │  [NAT GW 2] [ALB]  │
              └─────────┬─────────┘     └─────────┬─────────┘
                        │                          │
              ┌─────────▼─────────┐      ┌─────────▼─────────┐
              │  Private-RT-AZ1    │      │  Private-RT-AZ2    │
              │  0.0.0.0/0→NAT GW1 │      │  0.0.0.0/0→NAT GW2 │
              └─────────┬─────────┘      └─────────┬─────────┘
              ┌─────────▼─────────┐      ┌─────────▼─────────┐
              │Private-Subnet-AZ1  │      │Private-Subnet-AZ2  │
              │ 10.0.10.0/24 [App] │      │ 10.0.20.0/24 [App] │
              └─────────┬─────────┘      └─────────┬─────────┘
                        │                          │
              ┌─────────▼──────────────────────────▼─────────┐
              │              Isolated Route Table              │
              │         no 0.0.0.0/0 route — VPC-local only    │
              └─────────┬──────────────────────────┬─────────┘
              ┌─────────▼─────────┐      ┌─────────▼─────────┐
              │Isolated-Subnet-AZ1 │      │Isolated-Subnet-AZ2 │
              │10.0.100.0/24 [DB]  │      │10.0.200.0/24 [DB]  │
              └────────────────────┘      └────────────────────┘
```

- **Public tier** — Internet-facing (ALB), routed to the Internet Gateway.
- **Private tier** — application layer, outbound-only Internet access via a
  dedicated NAT Gateway per AZ (no single point of failure).
- **Isolated tier** — database layer, no route to the Internet at all
  (neither IGW nor NAT); traffic stays strictly within the VPC's
  `10.0.0.0/16` CIDR.

Security is enforced at two independent layers — see
[`configs/network_matrix.md`](configs/network_matrix.md) for the full
allow/deny table:

- **Security Groups** (stateful): `SG-ALB` → `SG-App` → `SG-DB`, each tier
  only accepting traffic from the tier in front of it, referenced by
  security group id (never by IP).
- **Network ACL** (stateless): a dedicated NACL on the isolated subnets,
  explicitly denying all Internet traffic and allowing only the private
  subnet CIDRs.

## Repository layout

```
proj01_custom_vpc/
├── Makefile
├── README.md
├── configs/
│   └── network_matrix.md
└── scripts/
    ├── deploy_vpc.sh
    ├── apply_network_security.sh
    └── cleanup_vpc.sh
```

## Prerequisites

- `aws-cli v2`, configured with credentials that have EC2 network
  permissions (see `Projet 00 — AWS Identity & Security Baseline` for the
  IAM setup used here).
- `bash`.
- No default VPC dependency: this project refuses to touch the AWS Default
  VPC and creates its own from scratch.

## Usage

```bash
make            # deploy the full architecture (~3-5 minutes)
make deploy     # same as above
make network-security  # re-apply only the security groups + NACL
make clean      # tear down every proj01 resource, in dependency order
make help       # list all targets
```

Every script is idempotent: running `make deploy` twice in a row never
creates duplicate resources or raises AWS CLI errors. Every resource is
looked up by its `Name` + `Project=proj01` tags before anything is created,
so a script can be safely re-run after a partial failure (e.g. a transient
API error, or Ctrl-C mid-run).

## Design conventions

- Every script starts with `set -euo pipefail`.
- Every AWS-created resource carries a standardized `Name` tag plus
  `Project=proj01`, used both for idempotency lookups and for cleanup.
- No hardcoded IDs: every VPC/subnet/route-table/security-group id is
  captured directly from the AWS CLI via `--query ... --output text`, then
  threaded through the rest of the script as a shell variable.
- Each resource follows the same inline pattern: `describe` to check if it
  already exists, `if` to skip creation when it does, `create` otherwise.
  `deploy_vpc.sh` additionally defines one helper, `wait_until_visible`,
  to poll around EC2's eventual consistency right after a `create-*` call.

## Scripts

### `scripts/deploy_vpc.sh`

Provisions, in order: the VPC, the 6 subnets, the Internet Gateway, the
Public Route Table, both NAT Gateways (started in parallel to cut the wait
time in half) with their Private Route Tables, the Isolated Route Table
(deliberately left without a default route), network security (by invoking
`apply_network_security.sh`), and finally the S3 VPC Endpoint attached to
both private route tables.

### `scripts/apply_network_security.sh`

Configures the two security layers described in the network matrix:
Security Groups (`SG-ALB`, `SG-App`, `SG-DB`) and the isolated-subnets NACL.
Can be run standalone (`make network-security`) to re-sync security rules
without touching the network layout, or is invoked automatically as the
last step of `deploy_vpc.sh`.

### `scripts/cleanup_vpc.sh`

Tears down every resource created above, in strict dependency order:

1. NACL — subnets are moved back to the default NACL before the custom one
   is deleted (AWS refuses to delete a NACL still associated with a
   subnet).
2. Security Groups — cross-referencing ingress rules are revoked
   (DB→App, App→ALB) before the groups themselves are deleted, since a
   security group cannot be deleted while another group holds a rule
   referencing it.
3. Isolated Route Table, then the S3 VPC Endpoint (a Gateway endpoint
   attached to the private route tables, so it must go before they do).
4. Each NAT Gateway is deleted and its deletion is **actively waited on**
   (`aws ec2 wait nat-gateway-deleted`) before its Elastic IP is released
   and its private route table is removed — attempting either earlier
   fails, since AWS takes several minutes to fully release a NAT Gateway.
5. Public Route Table, then the Internet Gateway.
6. All 6 subnets.
7. The VPC itself.

## Cost awareness

NAT Gateways and their Elastic IPs are billed hourly (plus data processing)
for as long as they exist. Run `make clean` as soon as you're done
verifying the architecture — `cleanup_vpc.sh` actively waits for both NAT
Gateways to be fully deleted, so the deallocation is confirmed, not just
requested, before the command returns.
