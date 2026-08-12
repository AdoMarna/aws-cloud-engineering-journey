# proj00_iam_baseline — AWS Identity & Security Baseline

Automation of a secure IAM baseline via AWS CLI v2, without going through the web console (except for the initial AWS account creation and Root MFA setup).

## Layout

```text
.
├── Makefile
├── README.md
├── policies/
│   ├── dev_restricted_policy.json
│   └── enforce_mfa_policy.json
└── scripts/
    ├── setup_iam.sh
    ├── assume_admin_role.sh
    └── cleanup_iam.sh
```

## Prerequisites

- `aws-cli` v2
- `jq`
- `session-manager-plugin`
- A non-root IAM user already configured as the default in the AWS CLI (`aws configure` / default profile), with enough rights to create an IAM role and assume it.

## Installation

```bash
make install
```

Copies the scripts from `scripts/` to `$(PREFIX)/bin` (defaults to `/usr/local/bin`), executable. `make uninstall` removes them.

`make install` provisions **nothing** on the AWS side — see below for why.

## Why `assume_admin_role.sh` must be sourced, not run via `make`

`assume_admin_role.sh` exports temporary admin role credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) that need to survive in the user's shell. Every Make recipe runs in a subshell that dies at the end of the recipe, so no variable exported by a `make` recipe can propagate back to the terminal that invoked it. Running this script via `make` would therefore silently discard the exported credentials as soon as the command ends.

`assume_admin_role.sh` must be **sourced directly**, from the project root (it references `scripts/` and `policies/` via relative paths).

`setup_iam.sh` and `cleanup_iam.sh`, on the other hand, don't need to be sourced — they don't leave any variables in the caller's shell (`setup_iam.sh` sources `assume_admin_role.sh` internally, but only for its own process; those temporary credentials never reach your shell). They can be run directly or via `make setup` / `make clean`.

## Usage

From a clean terminal, at the project root:

```bash
make install

# Provisions the group, the policies, the dev user, the password policy,
# and temporarily switches to an admin role (EmergencyAdminRole)
# to perform the operations that require it.
make setup
```

`setup_iam.sh`:
1. Checks prerequisites and refuses to continue if the current identity is root.
2. Sources `assume_admin_role.sh` to obtain temporary admin credentials (1h), scoped to its own process.
3. Creates the `Developers-Group` group, the `dev_restricted_policy.json` and `enforce_mfa_policy.json` policies, and attaches them to the group.
4. Creates the `dev-user-01` user and adds it to the group.
5. Configures the account password policy (16 char minimum, complexity requirements, 90-day expiration, prevents reuse of the last 5).
6. Generates an access key for `dev-user-01` and configures the `aws-dev-profile` CLI profile.

### Checking the developer profile's permissions

```bash
aws ec2 describe-instances --profile aws-dev-profile   # should work
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --profile aws-dev-profile   # should be denied
```

### Manually assuming the admin role (outside of setup)

```bash
source scripts/assume_admin_role.sh
```

Exports `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` for the `EmergencyAdminRole` role (valid 1h), based on the shell's current IAM identity.

### Cleanup

```bash
make clean
# or directly:
scripts/cleanup_iam.sh
```

Tears down, in order: access key, password policy, group membership, attached policies (group and role), custom policies, the `EmergencyAdminRole` role, the user, the group.

Like `setup_iam.sh`, this script does not need to be sourced: it resolves policy ARNs itself (via `aws iam list-policies --scope Local`) and the user's access key (via `aws iam list-access-keys`) by name, rather than depending on environment variables left by `setup_iam.sh`. It can therefore be run in a fresh terminal, at any time after setup.

## Security

No access key, secret, or Account ID is ever written in plaintext in the code: everything goes through environment variables or the AWS CLI configuration file (`~/.aws/credentials`).
