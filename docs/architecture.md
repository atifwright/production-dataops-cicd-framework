# Architecture and operations

## Components and trust boundaries

```text
Untrusted pull-request code
       |
       +--> CI job: contents:read
            Terraform format / init without backend / validate
            No AWS credentials, no OIDC permission, no apply

Reviewed main branch + manual workflow dispatch
       |
       +--> protected GitHub Environment
            environment-specific role ARN, region, state bucket and state key
            production: required reviewers and explicit confirmation
       |
       +--> GitHub Actions OIDC token (audience sts.amazonaws.com)
            subject restricted to repository + GitHub Environment
       |
       +--> AWS IAM deployment role (short-lived STS session)
            |
            +--> environment-specific S3 Terraform state
            +--> named pipeline-artifact S3 bucket
            +--> narrowly named IAM deployer role
```

`ci.yml` is intentionally credential-free. `deploy.yml` runs only through
`workflow_dispatch`, selects from a fixed allowlist of GitHub environments, uses
deployment-environment configuration, saves a plan and applies that plan in the
same workflow run. Concurrency is serialized per environment to avoid
overlapping changes.

## Terraform resources

Terraform provisions an encrypted, versioned, public-access-blocked S3 artifact
bucket; enforced S3 bucket ownership; a cleanup lifecycle for incomplete
multipart uploads; and an IAM role whose trust policy requires both the expected
GitHub repository/environment subject and AWS STS audience. Resource names,
environment, and tags are configuration driven.

The role policy permits managing the named artifact bucket, accessing the
configured environment-specific Terraform state key, and reading its own IAM
role during Terraform refresh. It does not grant permission to change IAM
roles, policies, or trust. A trusted bootstrap operator must apply IAM changes.
Assess permissions against AWS provider API requirements in a non-production
account. Extend permissions only for the services the actual pipeline workloads
require.

## Remote state bootstrap

The state bucket and GitHub OIDC provider are prerequisites, not resources this
root module creates. This avoids an impossible dependency on the state backend
before Terraform can initialize. Bootstrap them in an independently managed,
access-controlled process. The state bucket should have encryption, versioning,
public-access blocks, restricted access, and recovery controls. Keep state keys
distinct between environments. Terraform S3 native lock files are enabled using
`use_lockfile=true`.

## Environment contract

| Setting | Development | Production |
| --- | --- | --- |
| GitHub Environment | `development` | `production` |
| Terraform environment input | `dev` | `prod` |
| State key | Dedicated development key | Dedicated production key |
| GitHub approval | Configure according to team policy | Require designated reviewers |
| Apply confirmation | Manual workflow dispatch | Manual dispatch plus `deploy-production` |
| AWS role | Dev-scoped OIDC deployer | Prod-scoped OIDC deployer |

Keep each environment's state key, role ARN, account scope, bucket name, and
GitHub protection independent. Review cross-account role trust explicitly if
environments deploy into different AWS accounts.

## Operational runbook

1. Review and merge infrastructure changes through protected pull requests.
2. Verify CI succeeded.
3. Trigger the deploy workflow for the intended protected environment.
4. Confirm the environment, approval, and production confirmation if applicable.
5. Review job output and Terraform's plan before the apply step.
6. Verify bucket and role outputs in the target AWS account.
7. On failure, inspect the failed Terraform operation, check state and cloud
   resource status, and reconcile before retrying. Do not delete or replace
   state as an initial recovery action.

Define organization-specific alert delivery, audit-log retention, drift
detection, state recovery, incident escalation, and service-level objectives
before using for production workloads.

## Extending to data workloads

Add workload-specific steps as separately reviewed, least-privilege jobs or
reusable workflows. Use workload identity federation where supported, explicit
artifact and dataset boundaries, immutable dependency/tool versions, quality
and integration tests before publication, deployment approvals, and rollback
instructions. Do not pass raw customer data through workflow logs or artifacts.
