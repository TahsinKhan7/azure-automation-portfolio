# CI helper scripts

Small, dependency-free shell scripts shared by the GitHub Actions workflows in
`.github/workflows/` and the Azure DevOps pipelines in `azure-devops-pipelines/`.
Keeping the logic here means both CI systems run exactly the same checks and a
developer can run them locally before pushing.

| Script | Purpose | Used by |
|--------|---------|---------|
| `validate-json.sh` | Parses every `*.json` file (ARM templates, parameter files, configs) with `python -m json.tool`; emits GitHub or Azure Pipelines annotations for invalid files. | `ci.yml` (arm-ttk job), `adf-pipeline-deploy.yml` |
| `terraform-validate-all.sh` | Discovers `terraform/modules/*` and `terraform/environments/*`, runs `terraform init -backend=false` and `terraform validate` in each; `--fmt` adds `terraform fmt -check`, `--list` prints the directories as JSON for a job matrix. | `ci.yml` (terraform jobs), `terraform-plan-apply.yml` |
| `install-kubeconform.sh` | Installs a pinned [kubeconform](https://github.com/yannh/kubeconform) release and verifies its SHA-256 before use. | `ci.yml` (kubernetes-validate), `kubernetes-deploy.yml` |
| `install-databricks-cli.sh` | Installs a pinned [Databricks CLI](https://github.com/databricks/cli) release and verifies its SHA-256 before use. | `cd-pipeline.yml`, `databricks-bundle-deploy.yml` |

## Conventions

- `set -euo pipefail` everywhere; a failing check fails the script.
- Binaries are pinned to an exact version **and** a SHA-256 taken from the upstream
  release checksum file. Overriding the version requires supplying the matching checksum.
- Scripts take paths as arguments and never `cd` into untrusted directories.
- Python is invoked with `-I` (isolated mode) so a stray module next to the data cannot be imported.

## Running locally

```bash
scripts/ci/validate-json.sh
scripts/ci/terraform-validate-all.sh --fmt
scripts/ci/terraform-validate-all.sh terraform/modules/storage-account
scripts/ci/install-kubeconform.sh "$HOME/.local/bin"
```
