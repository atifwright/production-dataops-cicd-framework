# Production DataOps and CI/CD Framework

A Terraform and GitHub Actions starter for repeatable infrastructure delivery
and controlled deployment of data-pipeline environments. The project provisions
an AWS artifact bucket and a repository/environment-scoped GitHub Actions OIDC
role, and includes CI validation plus an explicitly triggered infrastructure
deployment workflow.

> **Status:** Runnable infrastructure starter, not a turnkey deployment of
> application-specific data pipelines. AWS credentials, state storage,
> environment configuration, and GitHub approval rules must be configured
> before deployment. Review IAM permissions and your organization's security
> requirements before use.

## Architecture

```text
Pull request / push to main
        |
        v
GitHub Actions CI
  terraform fmt -check
  terraform init -backend=false
  terraform validate

Manual workflow dispatch
        |
        v
Protected GitHub Environment
  environment approval / scoped variables
        |
        v
GitHub-issued OIDC token
        |
        v
AWS IAM deployment role
        |
        +---- encrypted, versioned S3 Terraform state
        |
        +---- Terraform plan and apply
                  |
                  +---- private, encrypted, versioned
                        pipeline-artifact S3 bucket
```

Detailed design, trust boundaries, setup order, and production considerations
are documented in [docs/architecture.md](docs/architecture.md).

## Repository layout

```text
.
├── .github/workflows/
│   ├── ci.yml                      # Formatting and Terraform validation
│   └── deploy.yml                  # Manually dispatched, OIDC-authenticated deploy
├── docs/
│   └── architecture.md             # Architecture, bootstrap, operations, and security
├── terraform/
│   ├── environments/
│   │   ├── dev.tfvars.example      # Development example inputs
│   │   └── prod.tfvars.example     # Production example inputs
│   ├── main.tf                     # Artifact bucket and scoped deployment role
│   ├── outputs.tf                  # Bucket and role outputs
│   ├── variables.tf                # Validated environment configuration
│   └── versions.tf                 # Terraform, AWS provider, and S3 backend
├── .gitignore
└── .terraform-version
```

## Prerequisites

- Terraform `1.9.x` and AWS provider `5.x` (the CI workflow pins Terraform
  `1.9.8`).
- An AWS account and a trusted operator identity for bootstrapping infrastructure.
- An existing AWS IAM OIDC provider for
  `https://token.actions.githubusercontent.com` in the target AWS account.
- An existing, versioned, encrypted S3 bucket for Terraform state.
- GitHub Actions environments named `development` and `production`.
- AWS credentials are supplied to GitHub Actions through short-lived OIDC role
  assumption; no long-lived AWS access keys are required by the workflow.

## Getting started

### 1. Bootstrap remote Terraform state

Provision the state bucket and GitHub OIDC provider separately using your
organization's approved AWS bootstrap process. The deployment role created by
this Terraform configuration cannot bootstrap its own state bucket or OIDC
provider. Enable bucket versioning and encryption, restrict public access, and
grant access only to trusted state administrators and deployment roles.

Set a unique Terraform state key for each environment, for example:

```text
production-dataops/dev/terraform.tfstate
production-dataops/prod/terraform.tfstate
```

Terraform uses S3 state locking via `use_lockfile=true`. The state bucket must
exist before running `terraform init`.

### 2. Configure GitHub environments

Create `development` and `production` in repository **Settings → Environments**.
For `production`, configure required reviewers and any branch restrictions
required by your release policy. Define these non-secret **environment
variables** for each environment:

| Variable | Example | Purpose |
| --- | --- | --- |
| `AWS_REGION` | `us-east-1` | AWS deployment region |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/dataops-dev-github-deployer` | OIDC role to assume |
| `TF_STATE_BUCKET` | `company-terraform-state` | Pre-provisioned remote state bucket |
| `TF_STATE_KEY` | `production-dataops/dev/terraform.tfstate` | Unique environment state key |

Use the production role and a distinct state key in the `production` environment.
The `AWS_DEPLOY_ROLE_ARN` must refer to a role whose trust policy restricts
assumption to this repository **and** the corresponding GitHub Environment.
Protect production with required reviewers; the workflow additionally requires
the manual `deploy-production` confirmation phrase.

### 3. Configure Terraform inputs and initialize

Copy the matching example file to an untracked environment-specific `.tfvars`
file and set an S3 bucket name that is globally unique:

```powershell
Copy-Item terraform\environments\dev.tfvars.example terraform\environments\dev.tfvars
# Edit dev.tfvars: select the region and a unique artifact_bucket_name.

cd terraform
terraform init `
  -backend-config="bucket=YOUR_PREEXISTING_STATE_BUCKET" `
  -backend-config="key=production-dataops/dev/terraform.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"
terraform validate
terraform plan -var-file=environments\dev.tfvars
```

The `terraform` working directory uses an S3 backend. For a first-time bootstrap,
use a separate state or a separately managed bootstrap configuration to create
the state bucket. Do not store Terraform state or plans in Git.

### 4. Apply infrastructure and register its deployment role

Apply with an authorized bootstrap operator identity. Configure the resulting
`github_deployer_role_arn` Terraform output as the appropriate GitHub
environment's `AWS_DEPLOY_ROLE_ARN`. Configure the trust relationship's GitHub
Environment subject to match the `github_environment` Terraform input (`development`
or `production`). The OIDC provider must already be present in AWS.

The workflow role can manage this starter's artifact bucket, access only its
configured state key, and read its own IAM role for Terraform refresh. It does
not grant permission to modify IAM roles or policies. Apply IAM trust or policy
changes with a trusted bootstrap operator. It is not a general-purpose
deployment role for arbitrary pipeline infrastructure. Extend the policy
narrowly for the specific services a data workload needs.

## CI and deployment

Every pull request and push to `main` runs `terraform fmt -check -recursive`,
initializes the Terraform providers without a state backend, and validates the
configuration. No AWS credentials or apply permissions are granted to CI.

Deploy via **Actions → Deploy infrastructure → Run workflow**. Select
`development` or `production`. The job enters the corresponding protected
GitHub Environment, assumes the configured AWS role through OIDC, initializes
the remote state, creates a saved Terraform plan, and applies that exact plan.
For production, enter `deploy-production` and satisfy the environment's required
reviewers.

## Provisioned resources

- An S3 bucket for pipeline artifacts with public-access blocks, enforced bucket
  ownership, default server-side encryption, versioning, and cleanup of
  incomplete multipart uploads.
- An IAM deployment role with a GitHub repository and environment-specific OIDC
  trust condition.
- A narrowly scoped inline policy for managing the artifact bucket and the
  project deployment role.

The starter does not provision data warehouses, pipeline schedulers, compute,
networking, or data transformation tools. Adapt the infrastructure and
workflows for the actual execution platform and workload.

## Security and operations

- Use protected branches, required pull-request reviews, and protected GitHub
  deployment environments, especially for production.
- Keep state, plan files, credentials, customer data, and environment-specific
  `.tfvars` out of version control.
- Restrict the state bucket and artifact bucket to approved identities; review
  IAM policies before adding deployment permissions.
- Pin and update GitHub Actions to reviewed immutable commit SHAs under your
  organization's supply-chain policy.
- Review the plan and configure drift detection, monitoring, retention,
  backup, incident response, and recovery policies before production use.

## License

No license has been selected. Add a license before granting permissions to
reuse or redistribute this project.
