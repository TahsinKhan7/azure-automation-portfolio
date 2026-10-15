# ADR 0003: Terraform modules composed by byte-identical environment roots

Status: accepted

## Context

Per-environment Terraform folders tend to drift: a fix lands in `dev`, a hotfix lands in `prod`, and six months later the two differ in ways nobody can explain. Workspaces avoid duplication but make it easy to plan against the wrong state, and a single pipeline identity with rights to every state file is a blast-radius problem.

## Decision

Put all resource logic in reusable modules under [`terraform/modules`](../../terraform/modules/) and give each environment its own root under [`terraform/environments`](../../terraform/environments/) whose `main.tf`, `variables.tf`, `versions.tf` and `outputs.tf` are byte-for-byte identical (verifiable with `md5sum`). Only `terraform.tfvars` and the backend state key differ. Each environment has its own state blob accessed through OIDC and Entra ID, and the pipeline's service connection for an environment holds rights to only that key. Optional resources are toggled with explicit booleans paired with `precondition` checks rather than `var.id != null`, which fails at first plan. Names are computed once in a provider-free `naming` module and consumed everywhere.

## Consequences

- Environment differences are reviewable as data in a single tfvars diff.
- A change cannot reach `prod` without having passed through the identical code in lower environments.
- Adding a variable is the only way to make something environment-specific, which forces the discussion of whether it should be.
- Native `terraform test` with `mock_provider` covers module logic offline ([`terraform/tests`](../../terraform/tests/)); provider behaviour is still only proven by `plan` against a real subscription.
- The Databricks provider is configured from the workspace module's outputs, so a first apply creates the workspace before any `databricks_*` resource is attempted.
