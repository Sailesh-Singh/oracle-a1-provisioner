# Oracle A1 Self-Provisioner

Automated provisioning of an Oracle Cloud Ampere A1 Always Free compute instance using GitHub Actions, OCI CLI, and cloud-init.

## Infrastructure

- Region: `ap-mumbai-1` (Mumbai)
- Shape: `VM.Standard.A1.Flex`
- Initial allocation: 1 OCPU / 2 GB RAM
- Operating system: Ubuntu 24.04
- Bootstrap: Docker, UFW, Fail2ban, automatic security updates

## Automation

GitHub Actions can be triggered manually or on a six-hour schedule. The provisioning script checks whether `main-server` already exists before attempting to create another instance.

It tries the available availability domains when A1 capacity is unavailable.

Scheduled GitHub Actions executions may be delayed by GitHub.

## Repository setup

Add these GitHub repository secrets under Settings > Secrets and variables > Actions:

- `OCI_CLI_TENANCY`
- `OCI_CLI_USER`
- `OCI_CLI_FINGERPRINT`
- `OCI_CLI_KEY_CONTENT` (complete private API key PEM content)
- `OCI_COMPARTMENT_ID`
- `OCI_SUBNET_ID`
- `OCI_SSH_PUBLIC_KEY`

Never commit private keys, `.env` files, or credentials.

## Local execution

The provisioning script runs in Bash and requires OCI CLI, jq, and access to the OCI API.

Copy `.env.example` to `.env`, fill in your values, configure OCI CLI authentication, then load the environment variables in Bash before running `scripts/provision.sh`.

## Important

Always Free eligibility and capacity are controlled by Oracle. A successful workflow run does not guarantee that capacity is available. Check the OCI Console to confirm the instance state and public IP.
