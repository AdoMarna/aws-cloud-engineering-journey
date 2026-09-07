# proj06_serverless_event_driven — Serverless Event-Driven Processing Engine (API Gateway, Lambda, DynamoDB, SQS & EventBridge)

A fully serverless, event-driven order pipeline provisioned end-to-end with **Terraform (v1.10+)**. HTTP traffic is validated and buffered asynchronously for zero-loss resilience, persisted in DynamoDB, and fanned out to downstream consumers via an EventBridge custom event bus. No servers, no idle compute cost — every component scales to zero and pays only per invocation.

## Architecture

```text
                                  Client Request
                                         │
                                         ▼
                            ┌────────────────────────┐
                            │   Amazon API Gateway   │ (HTTP API v2)
                            │   POST /orders         │
                            └────────────┬───────────┘
                                         │
                                         ▼
                            ┌────────────────────────┐
                            │   AWS Lambda (Ingest)  │ (Validation & Enqueue)
                            └────────────┬───────────┘
                                         │
                                         ▼
                            ┌────────────────────────┐
                            │    Amazon SQS Queue    │ (Buffer & Resilience)
                            │  + Dead-Letter Queue   │ (DLQ, maxReceiveCount=3)
                            └────────────┬───────────┘
                                         │ Event Source Mapping (batch=5)
                                         ▼
                            ┌────────────────────────┐
                            │  AWS Lambda (Processor)│ (Business Logic)
                            └──────┬──────────┬──────┘
                                   │          │
                 ┌─────────────────┘          └─────────────────┐
                 ▼                                              ▼
    ┌────────────────────────┐                      ┌────────────────────────┐
    │    Amazon DynamoDB     │                      │   Amazon EventBridge   │
    │  (Orders Table - NoSQL)│                      │    (Custom Event Bus)  │
    └────────────────────────┘                      └───────────┬────────────┘
                                                                │ Rule match
                                                                │ detail-type=OrderProcessed
                                                                ▼
                                                    ┌────────────────────────┐
                                                    │  AWS Lambda (Notifier) │
                                                    └────────────────────────┘
```

State locking and remote storage management:

```text
┌─────────────────────────────────────────────────────────────────┐
│                   Terraform Remote Backend                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Amazon S3 Bucket (proj06-bucket)            │   │
│  │   Encrypted (AES256), Versioned, Native S3 Lockfile      │   │
│  │       (use_lockfile = true — no DynamoDB table)          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Repository layout

```text
proj06_serverless_event_driven/
├── Makefile
├── README.md
├── main.tf                    # Root module: orchestrates all modules + EventBridge rule/target
├── variables.tf                # environment variable (dev/prod), applied via provider default_tags
├── outputs.tf                  # API endpoint, DynamoDB table, SQS URL, event bus, backend state
├── backend.tf                  # S3 remote backend with native S3 state locking
├── terraform.tfvars.example    # Template variable values
├── modules/
│   ├── api_gateway/            # HTTP API v2, route, Lambda proxy integration, access logs
│   ├── sqs/                    # Main queue + DLQ with redrive policy
│   ├── dynamodb/               # Orders table (PK/SK), PAY_PER_REQUEST
│   ├── eventbridge/             # Custom event bus
│   └── lambda/                 # Ingest, processor and notifier functions (dedicated IAM roles)
├── src/
│   ├── ingest/index.js         # Validates payload, enqueues to SQS, returns 202
│   ├── processor/index.js      # Consumes SQS batch, writes to DynamoDB, publishes OrderProcessed
│   └── notifier/index.js       # Consumes OrderProcessed events, simulates a notification
├── environments/
│   ├── dev.tfvars
│   └── prod.tfvars
└── scripts/
    ├── test_pipeline.sh        # End-to-end smoke test: HTTP -> SQS -> DynamoDB -> EventBridge -> notifier logs
    └── cleanup_serverless.sh   # Full teardown of every proj06 resource
```

The S3 backend bucket itself is bootstrapped separately by [`../bootstrap/bootstrap.sh`](../bootstrap/bootstrap.sh), shared with the rest of this repository's projects.

## Prerequisites

* `terraform` (v1.10+, for native S3 state locking via `use_lockfile`), `aws-cli v2`, `jq`, `curl`, `bash`.
* AWS CLI configured with valid administrator/provisioning permissions.
* Node.js Lambda runtimes (`nodejs22.x`) — the AWS SDK v3 clients used in `src/` ship with the Lambda runtime, no `node_modules` to package.

## Usage

```bash
make bootstrap   # Provision the S3 backend bucket (versioned, encrypted)
make init        # Initialize Terraform backend and modules
make validate    # Format check + syntax/type validation
make plan        # Run terraform plan (ENV=dev by default, ENV=prod supported)
make apply       # Deploy the full serverless pipeline
make test        # Run scripts/test_pipeline.sh against the live stack
make clean       # Destroy the stack, then run scripts/cleanup_serverless.sh
make help        # Display target help

# Target a specific environment
make plan ENV=prod
make apply ENV=prod
```

### Verifying the pipeline manually

```bash
api_endpoint=$(terraform output -raw api_endpoint)

# Valid order — expect HTTP 202
curl -s -X POST "${api_endpoint}/orders" \
  -H "Content-Type: application/json" \
  -d '{"customerId":"cust-1","items":[{"sku":"SKU-42","qty":2}]}'

# Invalid order (missing customerId) — expect HTTP 400
curl -s -X POST "${api_endpoint}/orders" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"sku":"SKU-1","qty":1}]}'
```

## Design conventions

* Every Shell script starts with `set -euo pipefail` and is idempotent (safe to re-run).
* **Pure HCL / No CLI Creation**: 100% of the AWS infrastructure is declared in Terraform HCL. No resource is created manually or via `aws-cli`, aside from the one-time backend bootstrap.
* **Least-Privilege IAM**: each Lambda has its own dedicated IAM role. Ingest can only `sqs:SendMessage`; processor can only `dynamodb:PutItem` and `events:PutEvents`; notifier has no permissions beyond CloudWatch Logs.
* **Zero Hardcoded Config**: queue URLs, table names, and event bus names are injected into Lambdas exclusively through Terraform-managed environment variables.
* **Automated Packaging**: each Lambda's `src/` directory is zipped on the fly by Terraform's `archive_file` data source — no manual build step.
* **Dynamic Environment Tagging**: the `environment` variable (`dev`/`prod`) flows into every resource via the provider's `default_tags`.

## Scripts

### `scripts/test_pipeline.sh`

1. Resolves the deployed HTTP API endpoint by name.
2. Sends an invalid payload and asserts HTTP 400 (ingest-side validation).
3. Sends a valid payload and asserts HTTP 202, capturing the returned `orderId`.
4. Polls DynamoDB until the processor has persisted the order with `status = PROCESSED`.
5. Confirms the DLQ stays empty (no poison messages).
6. Polls the notifier's CloudWatch Logs for a mention of the order, confirming the EventBridge fan-out fired end to end.

### `scripts/cleanup_serverless.sh`

Idempotent teardown, in dependency order: event source mapping → EventBridge targets/rule/bus → Lambda functions → HTTP API → SQS queues (main then DLQ) → DynamoDB table → CloudWatch log groups → IAM roles (detach + inline delete + role delete). The remote state bucket is left intact.

## Security

* **Least-Privilege IAM**: no Lambda role uses managed policies beyond `AWSLambdaBasicExecutionRole`; every other permission is a scoped inline policy against a single resource ARN.
* **Asynchronous Decoupling**: the ingest Lambda never talks to DynamoDB or EventBridge directly — it only enqueues to SQS, so a downstream outage never blocks client-facing HTTP responses.
* **Dead-Letter Isolation**: messages that fail processing 3 times land in `orders-dlq` instead of blocking or looping the main queue.
* **State File Encryption**: `terraform.tfstate` is encrypted at rest (`AES256`) and versioned on Amazon S3, locked natively via S3 conditional writes (`use_lockfile`).
* **Zero Hardcoded Secrets**: no credentials, ARNs, or account IDs are hardcoded in `.tf` files — everything is passed via Terraform variables, module outputs, or Lambda environment variables.
