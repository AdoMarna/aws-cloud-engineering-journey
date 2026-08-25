# proj04_container_orchestration — Container Orchestration & Microservices (ECS Fargate & ECR)

Fully automated, idempotent provisioning of a containerized, highly
available microservices stack: two Node.js services (`proj04-app` and
`proj04-api`) built into minimal Docker images, pushed to private ECR
repositories, and run as ECS Fargate services behind a single public
Application Load Balancer that path-routes traffic to each one. No EC2
instance ever runs a container — Fargate is serverless compute only. No
console clicks — everything is built and torn down through `aws-cli v2`,
`docker`, `jq` and `bash`.

## Architecture

```
                              Internet traffic
                                     │
                                     ▼ (port 80)
                    ┌────────────────────────────────┐
                    │   Application Load Balancer      │
                    │   Public-Subnet-AZ1 / AZ2        │
                    │   SG-ALB: 80 from 0.0.0.0/0       │
                    └────────────┬─────────────────────┘
                                 │ Listener :80
                    ┌────────────┴─────────────────────┐
                    │  Rule /api/*        Rule /*        │
                    ▼                                    ▼
        Target Group my-ip-tg-one          Target Group my-ip-tg-two
        (proj04-api, port 8080)            (proj04-app, port 8080)
        health check: GET /health          health check: GET /
                    │                                    │
        ┌───────────┴───────────┐            ┌───────────┴───────────┐
        ▼                       ▼            ▼                       ▼
Private-Subnet-AZ1     Private-Subnet-AZ2   Private-Subnet-AZ1   Private-Subnet-AZ2
┌─────────────────┐   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ ECS Task         │   │ ECS Task         │ │ ECS Task         │  │ ECS Task         │
│ (Fargate)         │   │ (Fargate)         │ │ (Fargate)         │  │ (Fargate)         │
│ proj04-api:local  │   │ proj04-api:local  │ │ proj04-app:v2     │  │ proj04-app:v2     │
│ SG-App: 8080 from  │   │ SG-App: 8080 from  │ │ SG-App: 8080 from  │  │ SG-App: 8080 from  │
│ SG-ALB only        │   │ SG-ALB only        │ │ SG-ALB only        │  │ SG-ALB only        │
└─────────────────┘   └─────────────────┘  └─────────────────┘  └─────────────────┘
        my-service-ecs-api (desired 2)             my-service-ecs (desired 2)
                        cluster: proj04-cluster (FARGATE, no EC2)
```

Both target groups sit behind the **same** ALB and listener: a
path-pattern rule sends `/api/*` to `my-ip-tg-one` (the `proj04-api`
service) and `/*` to `my-ip-tg-two` (the `proj04-app` service) — this is
the Bonus 1 path-based routing. Both ECS services run in the private
subnets created by `proj01_custom_vpc`; this project provisions no
network of its own, it consumes proj01's VPC/subnets by tag lookup, the
same convention used by proj02 and proj03.

## Repository layout

```text
proj04_container_orchestration/
├── Makefile
├── README.md
├── Dockerfile           # proj04-app image (Node.js, multi-stage, alpine, non-root)
├── Dockerfile.api       # proj04-api image, same conventions
├── app/
│   └── server.js        # GET / and GET /health
├── api/
│   └── server.js        # GET /api and GET /health
├── scripts/
│   ├── deploy_containers.sh
│   ├── enable_ecs_autoscaling.sh
│   ├── deploy_new_version.sh
│   └── cleanup_containers.sh
└── templates/
    ├── policy.json               # ecsTaskExecutionRole trust policy
    ├── task_definition.json      # proj04-app task def (mutated in place by the scripts)
    └── task_definition_api.json  # proj04-api task def
```

## Prerequisites

- `aws-cli v2`, `docker`, `jq`, `bash`.
- Docker daemon reachable locally (Docker Desktop with WSL2 integration,
  or native Docker Engine).
- `proj01_custom_vpc` already deployed: this project looks up its VPC
  (`Project=proj01` tag) and the two private subnets
  (`Private-Subnet-AZ1/AZ2`) plus the two public subnets
  (`Public-Subnet-AZ1/AZ2`) by name, for the ALB and the Fargate tasks
  respectively.
- IAM permissions to create/push to ECR repositories, create the
  `ecsTaskExecutionRole` IAM role, CloudWatch log groups, security
  groups, an ALB with listener and target groups, and an ECS cluster with
  Fargate services.

## Usage

```bash
make            # build, push, and deploy the full ECS Fargate stack
make deploy     # same as above
make enable     # attach the CPU 60% target tracking scaling policy (2-6 tasks)
make update     # build a v2 image and roll it out with a forced deployment
make clean      # tear down every proj04 resource
make help       # list all targets
```

Every script is idempotent: running `make deploy` twice in a row never
creates duplicate resources. Each resource is looked up (`describe-*`) by
its name/tag before anything is created, so a script can be safely
re-run after a partial failure.

### Verifying the deployment

```bash
alb_dns=$(aws elbv2 describe-load-balancers --names my-load-balancer \
    --query "LoadBalancers[0].DNSName" --output text)

# Traffic alternates between the two Fargate tasks behind the app target group
for i in $(seq 1 10); do curl -s "http://$alb_dns/" | jq -c '{status, hostname}'; done

# Path-based routing to the API service
curl -s "http://$alb_dns/api" | jq

# Remote log inspection via CLI
aws logs describe-log-streams --log-group-name /ecs/proj04-app \
    --order-by LastEventTime --descending --max-items 1 \
    --query "logStreams[0].logStreamName" --output text
aws logs get-log-events --log-group-name /ecs/proj04-app \
    --log-stream-name "<stream-name-from-above>" --query "events[].message" --output text
```

## Design conventions

- Every script starts with `set -euo pipefail`.
- Every AWS-created resource carries a standardized `Name` tag plus
  `Project=proj04`, `Environment=dev`, used both for idempotency lookups
  and for cleanup.
- Each resource follows the same inline pattern: `describe`/`get` to
  check if it already exists, `if` to skip creation when it does,
  `create` otherwise.
- No hardcoded resource ARN/ID: `templates/task_definition.json` and
  `templates/task_definition_api.json` are mutated in place with
  `jq --arg` (never string concatenation) to inject the
  `executionRoleArn` and the ECR image URI at every `deploy_containers.sh`
  / `deploy_new_version.sh` run.
- No hardcoded credentials: image URIs are built from
  `aws sts get-caller-identity`, and Docker authenticates to ECR via
  `aws ecr get-login-password | docker login --password-stdin` (never a
  stored password).
- Target groups are `target-type ip` (mandatory for Fargate's `awsvpc`
  network mode — there is no EC2 instance to register) and `HTTP`, not
  `TCP`: an Application Load Balancer only supports `HTTP`/`HTTPS`
  target groups, and `--health-check-path` has no effect on a `TCP`
  target group.

## Scripts

### `scripts/deploy_containers.sh`

Provisions, in order:

1. Two ECR repositories (`proj04-app`, `proj04-api`) with
   `scanOnPush`/`SCAN_ON_PUSH` vulnerability scanning enabled.
2. Builds, tags and pushes both images (`Dockerfile` / `Dockerfile.api`)
   to their repositories.
3. `ecsTaskExecutionRole` IAM role (trust policy:
   `templates/policy.json`, principal `ecs-tasks.amazonaws.com` — the
   principal Fargate actually assumes to pull the image and ship logs,
   **not** `ecs.amazonaws.com`) with `AmazonECSTaskExecutionRolePolicy`
   attached.
4. Two CloudWatch log groups: `/ecs/proj04-app`, `/ecs/proj04-api`.
5. `SG-ALB` (inbound TCP/80 from `0.0.0.0/0`) and `SG-App` (inbound
   TCP/8080 **only** from `SG-ALB`).
6. `my-load-balancer`: internet-facing ALB across both public subnets.
7. Two target groups (`my-ip-tg-one` for the API, `my-ip-tg-two` for the
   app), `target-type ip`, `protocol HTTP`, port 8080, health check on
   `/health` and `/` respectively.
8. A listener on port 80 with two path-pattern rules: `/api/*` →
   `my-ip-tg-one`, `/*` → `my-ip-tg-two`.
9. Registers both Fargate task definitions (`FARGATE`, `awsvpc`, 256 CPU
   / 512 MiB), image URI and execution role injected via `jq`.
10. `proj04-cluster` ECS cluster, and the two Fargate services
    (`my-service-ecs`, `my-service-ecs-api`), desired count 2 each,
    deployed in the private subnets with `SG-App`, attached to their
    respective target group. Waits (`ecs wait services-stable`) until
    both are steady.

### `scripts/enable_ecs_autoscaling.sh`

Registers both services as Application Auto Scaling scalable targets
(min 2 / max 6 tasks) and attaches a target tracking scaling policy
(`cpu60-target-tracking-scaling-policy`) on
`ECSServiceAverageCPUUtilization` at 60%. Run after `deploy_containers.sh`,
via `make enable`.

### `scripts/deploy_new_version.sh`

Simulates a rolling update: builds a new `proj04-app` image tagged `v2`,
pushes it to ECR, patches `templates/task_definition.json` with the new
image URI via `jq`, registers the updated task definition, then
`aws ecs update-service --force-new-deployment` on `my-service-ecs` —
ECS launches the new `v2` tasks, waits for them to pass the target
group's health check, and only then drains and stops the old tasks, with
no drop in `runningCount` below the desired count.

### `scripts/cleanup_containers.sh`

Tears down every resource created above, in dependency order:

1. Both ECS services: any attached Application Auto Scaling policy and
   scalable target are removed first, then the service is scaled to 0
   and awaited (`ecs wait services-stable`) before `delete-service`.
2. `proj04-cluster`.
3. Every revision of both task definition families is deregistered
   (`ecs list-task-definitions --family-prefix` + a loop, not just the
   latest revision).
4. Listener (rules go with it) → load balancer
   (`elbv2 wait load-balancers-deleted`) → both target groups.
5. Local Docker images removed, both ECR repositories deleted
   (`--force`, purges all pushed image tags with them).
6. Both CloudWatch log groups.
7. `ecsTaskExecutionRole`: policy detached, then the role deleted.
8. `SG-App` before `SG-ALB` (App references ALB as its ingress source,
   so it must go first).

Every step is idempotent — a resource already gone is skipped with a log
line instead of failing, so the script can be re-run safely after a
partial teardown.

## Security

- **No direct internet exposure**: Fargate tasks live exclusively in
  private subnets with no public IP; the ALB in the public subnets is
  the only internet-facing resource.
- **Security Group chaining**: `SG-App` only accepts traffic whose
  source is `SG-ALB` — not a CIDR range — so tasks can never be reached
  except through the load balancer.
- **Fargate only**: `requiresCompatibilities: ["FARGATE"]` and
  `networkMode: "awsvpc"` in both task definitions — no EC2 instance
  ever runs application code, no host to patch or harden.
- **Non-root containers**: both Dockerfiles run the application as an
  unprivileged `app` user, never `root`.
- **Least-privilege execution role**: `ecsTaskExecutionRole` only carries
  `AmazonECSTaskExecutionRolePolicy` (ECR pull + CloudWatch Logs write),
  scoped to what Fargate needs to launch a task and ship its logs —
  nothing else.
- **Image scanning**: both ECR repositories have `scanOnPush` enabled,
  so every pushed image is scanned for known vulnerabilities
  automatically.
- No access key, secret, or Account ID is ever written in plaintext in
  the repository. `templates/task_definition*.json` are committed with
  the execution role ARN and image URI filled in by the scripts at
  runtime via `jq`, and Docker's ECR login goes through
  `get-login-password` piped straight into `docker login`, never a
  credential stored on disk.
