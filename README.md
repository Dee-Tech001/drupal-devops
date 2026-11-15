# Drupal DevOps on AWS

Terraform, Ansible, Docker Compose, and GitHub Actions for deploying and monitoring a Drupal application on AWS.

> **Production readiness: not production-ready as currently configured.** This repository contains exposed/default credentials and infrastructure security gaps. Review the [security findings](#security-findings) and resolve all Critical/High items before deploying or using real data.

## What is in this repository

- `terraform/` provisions a VPC, two public subnets, EC2 instances, a MySQL RDS instance, and an Application Load Balancer in `us-east-1`.
- `terraform/docker/` builds the Drupal image and defines a local Compose stack with MySQL.
- `terraform/ansible/` configures EC2 hosts and starts containers.
- `.github/workflows/ci-cd.yml` builds/tests an image, then pushes and deploys staging and production on pushes to `main`.
- `monitoring/` defines Prometheus, Grafana, and node-exporter Compose services.

## Architecture (current Terraform configuration)

The diagram reflects the checked-in Terraform, not a recommended production target. EC2 instances are in public subnets, the ALB has an HTTP listener, and the Terraform RDS instance is separate from the MySQL container in the Compose configuration. The application-to-database integration is not fully wired in the checked-in configuration.

```mermaid
architecture-beta
    group internet(cloud)[Public Internet]
    group aws(aws:cloud)[AWS us-east-1]
    group vpc(aws:vpc)[Drupal VPC]

    service igw(aws:internet-gateway)[Internet Gateway] in aws
    service alb(aws:alb)[Application Load Balancer HTTP] in vpc
    service ec2a(aws:ec2)[Drupal EC2 AZ-a public subnet] in vpc
    service ec2b(aws:ec2)[Drupal EC2 AZ-b public subnet] in vpc
    service rds(aws:rds)[RDS MySQL] in vpc

    internet:R -- L:igw
    igw:R -- L:alb
    alb:B -- T:ec2a
    alb:B -- T:ec2b
    ec2a:R -- L:rds
    ec2b:R -- L:rds
```

This uses Mermaid's `architecture-beta` syntax and AWS icon pack identifiers. The renderer must support Mermaid architecture diagrams and the AWS icon pack. If AWS icons are not available in the renderer, use the standard Mermaid flowchart renderer or install/register Mermaid's AWS icon pack.

## Prerequisites

- Terraform, Ansible, Docker with Compose, and AWS CLI.
- An AWS account with permissions limited to the required deployment resources.
- An SSH key pair. Do not commit private keys or state files.
- GitHub Actions secrets and protected `staging`/`production` environments as described under [CI/CD configuration](#cicd-configuration).

## Terraform

Run from `terraform/` after correcting the key path and reviewing the security findings:

```sh
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`terraform/main.tf` currently reads a developer-specific public key path (`~/.ssh/Addosser-key.pub`). Replace it with a configurable path or a securely managed key input before running. Supply `db_password` through a secure input mechanism; do not put it in source control or a committed `.tfvars` file. Terraform state and plan files can contain credentials and must be encrypted, access-controlled, and excluded from Git.

The configuration currently has no backend/state locking, and provisions public EC2 subnets and a non-TLS HTTP listener. Do not apply it to a production account without fixing these issues and reviewing the plan.

## CI/CD configuration

The active workflow expects these GitHub Actions secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `ECR_REGISTRY`
- `STAGING_SERVER_IP`
- `PROD_SERVER_IP`
- `SSH_PRIVATE_KEY`

Prefer GitHub Actions OIDC federation to long-lived AWS access keys, scope IAM permissions to the specific resources, pin third-party Actions to full commit SHAs, and use immutable image digests rather than mutable `staging`/`latest` tags. Configure required reviewers and branch protection for production. The workflow currently runs only `php -v` as a smoke check, and deploys through SSH; this is not a comprehensive test or release-validation process.

The workflow references secrets rather than containing AWS access-key values in its active file. Review any previously used values and Git history separately; deleting a credential from the current tree does not revoke it or remove it from history.

## Monitoring

`monitoring/docker-compose.monitoring.yml` starts Prometheus, Grafana, and node-exporter. `monitoring/prometheus.yml` contains placeholder targets and must be configured for the actual scrape endpoints. Do not expose Prometheus, Grafana, or node-exporter directly to the public internet. Configure authentication, network restrictions, persistent storage, TLS, alerting, and pinned image versions before operational use.

## Security findings

Static review of the current tracked files found the following. This is not a full Git-history, deployed-account, or runtime scan.

| Severity | Finding | Evidence / action |
| --- | --- | --- |
| **Critical** | Grafana default password is committed as `admin`. | `monitoring/docker-compose.monitoring.yml` sets `GF_SECURITY_ADMIN_PASSWORD=admin`. Treat it as compromised if ever deployed: rotate it immediately, check access logs, and load credentials from a secret manager. Do not expose Grafana publicly. |
| **High** | SSH is allowed from `0.0.0.0/0`. | `terraform/main.tf` opens port 22 to the world. Remove this rule; use Systems Manager Session Manager or tightly restricted administrative CIDRs and a controlled access path. |
| **High** | The same security group is attached to the ALB, EC2 instances, and RDS. | Separate ALB, application, and database security groups. Permit only ALB-to-app traffic and app-to-database traffic on the required ports. Keep database access private. |
| **High** | The ALB accepts plaintext HTTP only. | `terraform/main.tf` creates a port 80 listener. Add HTTPS with an ACM certificate, redirect HTTP to HTTPS, and use secure application/database connections as required. |
| **High** | RDS final snapshot is disabled. | `skip_final_snapshot = true` risks losing the final recoverable database snapshot on destroy. Enable deletion protection, backups, retention, and a final snapshot policy. Test restores. |
| **High** | Application/database design is inconsistent. | Terraform creates RDS, while Compose defines a separate MySQL container; no checked-in deployment wiring proves Drupal uses RDS. Choose and document one database architecture before production use. |
| **Medium** | Public server IPs and a local key-file path are committed. | `terraform/ansible/inventory.ini` contains two public IPs, and `terraform/main.tf` references a user-specific SSH public-key path. These are not private keys/passwords, but expose infrastructure details and reduce portability. Remove fixed hosts from inventory and use generated outputs/dynamic inventory; rotate/restrict hosts if exposed. |
| **Medium** | Docker images are not pinned to immutable versions/digests. | Compose uses `latest` for monitoring images; deployments use mutable tags. Pin reviewed versions/digests and scan images for vulnerabilities. |
| **Medium** | GitHub Actions uses long-lived AWS keys and SSH deployment credentials. | Migrate AWS authentication to OIDC, apply least privilege, protect environments, and rotate any credentials that have ever been exposed. |
| **Medium** | Terraform state security is not configured in this repository. | Configure a remote encrypted backend with access control and locking before collaborative or production use. Never commit state, plans, or secret-bearing variable files. |

### Secret scan summary

- No literal AWS access-key ID, AWS secret access key, or private-key block was found in the reviewed active Terraform, Docker, monitoring, and workflow files.
- A committed Grafana default password (`admin`) is present and must be treated as a leaked credential.
- The active workflow references GitHub Actions secrets; references are not themselves the secret values.
- Two workflow backup files (`.github/workflows/ci-cd.yml.save` and `.github/workflows/ci-cd.yml.save.1`) are tracked. They contain stale/malformed deployment snippets and secret references. Remove these backups and review the full repository history for any previously committed credentials.

Recommended follow-up: run a dedicated secret scanner (for example, Gitleaks) over the complete repository and Git history, enable GitHub secret scanning/push protection where available, rotate any credential that may have been used, and inspect deployed AWS resources and logs. A clean current-tree scan does not establish that a credential was never exposed.

## Repository description

Suggested GitHub repository description (the repository currently has no description):

> Terraform and Ansible automation for deploying a containerized Drupal application on AWS, with GitHub Actions CI/CD and Prometheus/Grafana monitoring.

## License

No license file is currently present. Add a license if you intend to grant reuse rights.
