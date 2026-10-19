# Contributing

This is a personal portfolio, but it is run like a shared codebase. Issues and pull requests are welcome; the conventions below keep the CI green and the history readable.

## Branches

Trunk-based: branch from `main`, keep branches short-lived, squash-merge back.

- `feat/<slug>` for new capability, `fix/<slug>` for corrections, `chore/<slug>` for tooling and dependencies, `docs/<slug>` for documentation only.
- Never push directly to `main`; the CI status check and a review are required.

## Commits and pull request titles

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `ci:`, `docs:`, `refactor:`, `test:`, `chore:`, with an optional scope such as `feat(terraform):` or `fix(python):`. Release notes are drafted from these titles by [release-drafter](.github/release-drafter.yml), so write them for a reader.

## Before you push

```bash
pip install pre-commit && pre-commit install
pre-commit run --all-files
```

The hooks in [`.pre-commit-config.yaml`](.pre-commit-config.yaml) mirror CI: whitespace and merge-marker checks, `ruff`, `terraform fmt`/`validate`/`tflint`, `yamllint`, `markdownlint` and `gitleaks`. Technology-specific test commands are in the root [README](README.md#running-things-locally).

## What CI checks

[`ci.yml`](.github/workflows/ci.yml) runs only the areas a pull request touches and aggregates them into one `ci-status` check: Python (ruff, pytest, wheel), Terraform (fmt, tflint, `terraform test`, validate per directory), Bicep build, ARM (JSON lint, ARM-TTK), PowerShell (PSScriptAnalyzer, Pester), Kubernetes (kustomize + kubeconform per overlay), SQL and Markdown lint (advisory), YAML lint (blocking), and the Databricks bundle validation when a workspace is configured. [CodeQL](.github/workflows/codeql.yml) scans the Python code.

## Pull request template

The [template](.github/PULL_REQUEST_TEMPLATE.md) asks for: a summary, the change type, the environments affected, validation evidence (plan or what-if output, test results, CI link), a rollback step, and a checklist confirming no secrets or identifiers are committed and documentation is updated. Fill it in; reviewers approve against the evidence, not the description.

## Non-negotiables

- No secrets, connection strings, subscription or tenant identifiers. Use placeholders (`00000000-...`, `203.0.113.x`, `example.com`).
- New behaviour arrives with a test in the same pull request.
- Environment differences are data (tfvars, bicepparam, bundle variables, overlays), never forked code.
- UK English in documentation and comments.

Security issues: follow [SECURITY.md](.github/SECURITY.md) rather than opening a public issue.
