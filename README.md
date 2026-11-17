
# Oracle A1 Self-Provisioner

Automated provisioning of an Oracle Cloud Ampere A1 Always Free compute instance using GitHub Actions, OCI CLI, and cloud-init.

## Overview

This project automates the provisioning of an Oracle Cloud Infrastructure Ampere A1 instance.

It supports manual execution and scheduled retries when Oracle A1 capacity is unavailable.

## Infrastructure

| Configuration | Value |
|---|---|
| Cloud provider | Oracle Cloud Infrastructure |
| Region | Mumbai (`ap-mumbai-1`) |
| Availability domains | Automatically discovered |
| Shape | `VM.Standard.A1.Flex` |
| OCPU | 1 |
| Memory | 2 GB |
| Operating system | Ubuntu 24.04 |
| Instance name | `main-server` |
| Network | Existing public subnet |
| Provisioning | OCI CLI |
| Automation | GitHub Actions |

## Features

- Automated Oracle A1 provisioning
- Manual GitHub Actions trigger
- Scheduled retries every five minutes
- Availability domain discovery
- Capacity error handling
- Existing-instance detection
- Ubuntu 24.04 cloud-init bootstrap
- Docker Engine and Docker Compose
- UFW firewall
- Fail2ban SSH protection
- Automatic security updates

## Architecture

```text
             GitHub Actions
                    |
                    v
              OCI CLI Setup
                    |
                    v
            OCI Authentication
                    |
                    v
           Instance Detection
                    |
                    v
        Availability Domain Discovery
                    |
                    v
             A1 Provisioning
                    |
          +---------+---------+
          |         |         |
         AD-1      AD-2      AD-3
          |         |         |
          +---------+---------+
                    |
                    v
          VM.Standard.A1.Flex
               1 OCPU
                2 GB
                    |
                    v
             Ubuntu 24.04
                    |
          +---------+---------+
          |         |         |
        Docker    UFW     Fail2ban
```

## Repository Structure

```text
oracle-a1-provisioner/
│
├── .github/
│   └── workflows/
│       └── provision.yml
│
├── cloud-init/
│   └── ubuntu.yaml
│
├── scripts/
│   └── provision.sh
│
├── .env.example
├── .gitignore
└── README.md
```

## GitHub Secrets

Go to:

Repository Settings → Secrets and variables → Actions

Create the following repository secrets:

| Secret | Description |
|---|---|
| `OCI_CLI_TENANCY` | OCI Tenancy OCID |
| `OCI_CLI_USER` | OCI User OCID |
| `OCI_CLI_FINGERPRINT` | API signing key fingerprint |
| `OCI_CLI_KEY_CONTENT` | Complete OCI API private PEM key |
| `OCI_COMPARTMENT_ID` | Root compartment OCID |
| `OCI_SUBNET_ID` | Public subnet OCID |
| `OCI_SSH_PUBLIC_KEY` | SSH public key |
| `OCI_ASSIGN_PUBLIC_IP` | Repository variable; set to `true` only when public access is required |

Never commit private keys, credentials, or `.env` files.

Before provisioning, edit `cloud-init/ubuntu.yaml` and replace `REPLACE_WITH_TRUSTED_CIDR` with your administrator's public IP in `/32` form. HTTP and HTTPS remain closed unless `PUBLIC_WEB_ACCESS=true` is configured in that file.

## GitHub Actions

The workflow supports:

### Manual execution

1. Open the repository Actions tab.
2. Select Oracle A1 Self Provisioner.
3. Click Run workflow.

### Scheduled execution

The workflow uses:

```yaml
schedule:
  - cron: "*/5 * * * *"
```

This requests execution every five minutes. GitHub may delay scheduled runs.

Scheduled workflows must be enabled and the workflow file must be on the repository's default branch.

## Local Execution

Requirements:

- Ubuntu, Linux, WSL, or Git Bash
- Python
- OCI CLI
- jq
- Bash

Configure OCI CLI:

```bash
oci setup config
```

Create the local environment file:

```bash
cp .env.example .env
```

Edit `.env` with your infrastructure details.

Load the environment and run:

```bash
set -a
source .env
set +a

bash scripts/provision.sh
```

The OCI CLI uses your local `~/.oci/config` and API private key.

## Instance Lifecycle

The script checks for an existing instance named `main-server` before provisioning.

If an instance already exists and is not terminated, the script exits without creating another one.

If Oracle reports unavailable A1 capacity, the script tries the next availability domain.

If all domains lack capacity, the next scheduled execution can retry.

## Security

- OCI API credentials are stored in GitHub Secrets.
- API private keys are never committed.
- SSH access is configured using a public key.
- UFW restricts inbound traffic to SSH, HTTP, and HTTPS.
- Fail2ban protects SSH against repeated failed login attempts.
- Ubuntu security updates are enabled.

Remember to configure the OCI subnet security rules for the required inbound ports as well.

## Important Notes

- Always Free eligibility is determined by Oracle.
- Capacity is not guaranteed.
- A successful launch request does not mean cloud-init has completed.
- Verify the instance lifecycle state and public IP in OCI Console.
- Monitor Always Free resource usage.

## License

MIT
