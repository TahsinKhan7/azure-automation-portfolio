# Security policy

## Reporting a vulnerability

Please report security issues through
[GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
for this repository (**Security** tab, then **Report a vulnerability**). Do not open a public issue.

Please include the affected file or module, the version or commit, and steps to reproduce. You will
receive an acknowledgement within five working days.

## Scope

This repository contains infrastructure code, pipelines and automation scripts. The most useful
reports are:

- committed secrets or identifiers (also enforced by gitleaks in pre-commit and secret scanning in CI)
- insecure defaults in Terraform, Bicep or ARM templates (public network access, missing encryption, over-broad RBAC)
- pipeline steps that could leak credentials into logs or artefacts
- unsafe Kubernetes manifests (privileged containers, missing resource limits, host mounts)

## Supported versions

Only the `main` branch is maintained. Fixes are released by tagging a new version from `main`.
