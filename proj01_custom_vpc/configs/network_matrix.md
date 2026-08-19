# Network Matrix — proj01 Custom Multi-AZ VPC

This document is the single source of truth for what traffic is allowed to
flow where in this VPC. It exists independently of the scripts: when
reviewing or auditing `apply_network_security.sh`, compare its rules against
this table rather than re-deriving intent from the code.

VPC CIDR: `10.0.0.0/16`

## Subnet layout

| Subnet | CIDR | AZ | Layer |
|---|---|---|---|
| Public-Subnet-AZ1 | `10.0.1.0/24` | eu-west-3a | Public (ALB, NAT) |
| Public-Subnet-AZ2 | `10.0.2.0/24` | eu-west-3b | Public (ALB, NAT) |
| Private-Subnet-AZ1 | `10.0.10.0/24` | eu-west-3a | Private (application) |
| Private-Subnet-AZ2 | `10.0.20.0/24` | eu-west-3b | Private (application) |
| Isolated-Subnet-AZ1 | `10.0.100.0/24` | eu-west-3a | Isolated (database) |
| Isolated-Subnet-AZ2 | `10.0.200.0/24` | eu-west-3b | Isolated (database) |

## Security Groups (stateful, Layer 1 of defense)

| Source | Destination | Port | Protocol | Allowed | Rationale |
|---|---|---|---|---|---|
| Internet (`0.0.0.0/0`) | SG-ALB | 80, 443 | TCP | ✅ | Public entry point for HTTP/HTTPS |
| SG-ALB | SG-App | 80, 443 | TCP | ✅ | Only the ALB may reach the application layer, referenced by security group id, never by IP |
| SG-App | SG-DB | 5432 | TCP | ✅ | Only the application layer may reach PostgreSQL, referenced by security group id |
| Internet | SG-App | any | any | ❌ | No direct public access to the application layer — must go through the ALB |
| Internet | SG-DB | any | any | ❌ | No direct public access to the database layer under any circumstance |
| Any | Any | any | any | (default deny) | Security groups deny by default; only the rules above are authorized |

## Network ACL (stateless, Layer 2 of defense — isolated subnets only)

A dedicated NACL (`MyNaclCustom`) is attached to `Isolated-Subnet-AZ1` and
`Isolated-Subnet-AZ2` in place of the VPC's default NACL.

| Direction | Rule # | CIDR | Protocol | Action | Rationale |
|---|---|---|---|---|---|
| Ingress | 100 | `10.0.10.0/24` (Private-Subnet-AZ1) | All | Allow | Application layer AZ1 may reach the database layer |
| Ingress | 110 | `10.0.20.0/24` (Private-Subnet-AZ2) | All | Allow | Application layer AZ2 may reach the database layer |
| Ingress | 120 | `0.0.0.0/0` | All | Deny | Explicitly block everything else, including the Internet |
| Egress | 100 | `10.0.10.0/24` (Private-Subnet-AZ1) | All | Allow | Database layer may answer the application layer AZ1 |
| Egress | 110 | `10.0.20.0/24` (Private-Subnet-AZ2) | All | Allow | Database layer may answer the application layer AZ2 |
| Egress | 120 | `0.0.0.0/0` | All | Deny | Explicitly block all outbound traffic to the Internet |

Net effect: the isolated subnets can only exchange traffic with the two
private subnets. No route to an Internet Gateway or NAT Gateway exists on
their route table either (see below) — isolation is enforced at both the
routing layer and the NACL layer, independently.

## Routing (proof of isolation)

| Route Table | Subnets | Default route (`0.0.0.0/0`) | Internet access |
|---|---|---|---|
| Public Route Table | Public-Subnet-AZ1, AZ2 | → Internet Gateway | Full (ingress + egress) |
| Private-RT-AZ1 | Private-Subnet-AZ1 | → NAT Gateway (AZ1) | Egress only |
| Private-RT-AZ2 | Private-Subnet-AZ2 | → NAT Gateway (AZ2) | Egress only |
| Isolated Route Table | Isolated-Subnet-AZ1, AZ2 | **none** | **None — local VPC traffic only** |

Verification command (used in the deployment "fire test"):

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=Isolated Route Table" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0']" \
  --output json
```

Expected output: `[]` — no default route exists, proving the isolated
subnets have no path to or from the Internet.

## VPC Endpoint

| Service | Type | Attached to | Purpose |
|---|---|---|---|
| S3 (`com.amazonaws.eu-west-3.s3`) | Gateway | Private-RT-AZ1, Private-RT-AZ2 | Keeps S3 traffic on the AWS private network instead of routing through the NAT Gateway, avoiding NAT data-processing charges |
