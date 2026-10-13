# GitHub Actions

CI/CD of this stack follows `GITHUB_ACTIONS_TF_RULES.md`. Two workflows:

| Workflow | Trigger | Jobs |
|---|---|---|
| `ci.yml` | `pull_request` to `main` | `terraform` (fmt, validate), `tflint`, `trivy` (report-only), `workflows` (actionlint, zizmor), `shellcheck`, `plan` (PR comment) |
| `cd.yml` | `push` to `main` (filtered by `paths:`) and `workflow_dispatch` | `plan` -> `apply` (approval, saved plan) -> `notify-failure` |

Nothing deploys from a branch or a PR. The apply job runs only when the plan has changes
(exit code 2) and applies the exact plan file the reviewer saw in the job summary.

## GitHub setup

**Variables** (Settings > Secrets and variables > Actions > Variables)

| Name | Value |
|---|---|
| `AWS_PLAN_ROLE_ARN` | output `ci_plan_role_arn` |
| `AWS_ROLE_ARN` | output `ci_apply_role_arn` |
| `TFSTATE_BUCKET` | name of the state bucket (also used as `TF_VAR_tfstate_bucket_name`) |

**Secrets**: `SSH_PUBLIC_KEY` (public key of the EC2 key pair Terraform creates). Never add
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`: authentication is OIDC only.

**Environments**: `plan` (no reviewers) and `production` (required reviewers, prevent
self-review if more than one person can approve, deployment branches restricted to `main`).

**Branch protection on `main`**: pull request required, no direct or force push, required checks
`Terraform fmt and validate`, `TFLint`, `Lint workflows`, `Terraform plan` (`Trivy config scan`
stays optional while it is report-only; switch `exit-code` to `"1"` once clean).

**Actions settings**: allow GitHub-created actions and the ones used here, require approval for
fork workflows, default token permission "Read repository contents". Enable Issues
(`notify-failure` opens one).

## AWS setup

- One GitHub OIDC provider per account (`token.actions.githubusercontent.com`, audience
  `sts.amazonaws.com`); this stack only reads it.
- The roles, the permissions boundary and their policies are in `ci_roles.tf`.
  - **plan** role: trusted from `environment:plan` and `ref:refs/heads/main`; read-only, and it can
    only write the `*.tflock` objects, never the state.
  - **apply** role: trusted from `environment:production` only, plus `ref = refs/heads/main` and
    `job_workflow_ref = <github_repository>/.github/workflows/cd.yml@refs/heads/main`.
- **Changes to `ci_roles.tf` are applied by hand from a workstation with admin credentials.** The
  pipeline fails with `AccessDenied` on them by design. The first apply of the stack is manual too.
- The state bucket is created by hand (versioned, encrypted). The backend uses `use_lockfile = true`
  (S3 native locking); the bucket name is passed at init, not stored in code:
  `terraform init -backend-config="bucket=<name>"`.

## Terraform version

`1.15.6`, written literally in every job of both workflows, and inside `required_version`
(`>= 1.10.0`) of `backend.tf`. When bumping it, change every occurrence.

## Checklist when touching a workflow

- Every new `uses:` pinned to a full commit SHA with the tag in a comment?
- Each job requests only the permissions it uses?
- Untrusted values (`github.head_ref`, PR title, `inputs.*`, secrets) go through `env:`, not into the script text?
- `timeout-minutes` set?
- Can it run from a fork or Dependabot? If it needs secrets/OIDC, is there an `if:` guard?
- Does apply apply the saved plan?
- Does the apply role still trust the `production` environment only (plus `ref` / `job_workflow_ref`)?
- Same Terraform version in every job and within `required_version`?
- New Terraform variable without a default: add the GitHub variable and the `TF_VAR_` line in `ci.yml` and `cd.yml`.
- Changed `ci_roles.tf`: applied by hand?

## Region (DR)

`cd.yml` accepts `aws_region` on `workflow_dispatch`. Any region other than `eu-west-1` uses the
state key `regions/<region>/terraform.tfstate`. Add the DR region to `ci_allowed_regions` and apply
that change by hand before deploying there.
