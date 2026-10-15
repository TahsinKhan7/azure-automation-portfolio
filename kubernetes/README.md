# Kubernetes (AKS) manifests

**What this demonstrates:** a production-shaped AKS deployment of a data API managed with Kustomize across five environments, with secrets pulled from Key Vault through the Secrets Store CSI driver and workload identity (no secrets in Git, no node-level identity), restricted Pod Security, default-deny network policies, HPA/PDB for resilience, an nginx ingress with cert-manager TLS, and Prometheus scraping through a ServiceMonitor. Validation is static (kubeconform + kustomize build) so it runs in CI without a cluster.

## Layout

| Path | Purpose |
|------|---------|
| `base/kustomization.yaml` | Environment-neutral resource list and common labels |
| `base/namespace.yaml` | Namespace with Pod Security Admission `restricted`, ResourceQuota, LimitRange |
| `base/serviceaccount.yaml` | Service account annotated for Azure Workload Identity |
| `base/configmap.yaml` | Non-sensitive application settings |
| `base/secretproviderclass.yaml` | Key Vault CSI provider: which secrets to mount and mirror into a Secret |
| `base/deployment.yaml` | Hardened Deployment (non-root, read-only FS, probes, spread constraints, CSI volume) |
| `base/service.yaml` | ClusterIP service exposing `http` and `metrics` |
| `base/hpa.yaml` | HorizontalPodAutoscaler on CPU and memory with scale-down stabilisation |
| `base/pdb.yaml` | PodDisruptionBudget for node drains during AKS upgrades |
| `base/networkpolicy.yaml` | Default deny, then allow ingress-nginx, monitoring and HTTPS egress |
| `base/ingress.yaml` | nginx Ingress with TLS from cert-manager and rate limiting |
| `base/servicemonitor.yaml` | Prometheus Operator scrape configuration |
| `overlays/<env>/kustomization.yaml` | Namespace, image tag, labels and inline JSON patches for the environment |
| `overlays/<env>/patch-configmap.yaml` | Environment settings (Key Vault name, storage account, log level) |
| `overlays/<env>/patch-deployment.yaml` | Environment resource requests and limits |

## Per-environment differences

Everything not listed here is identical across environments and lives in `base/`.

| Setting | dev | ite | iqe | preprod | prod |
|---------|-----|-----|-----|---------|------|
| Namespace | `dataplatform-dev` | `dataplatform-ite` | `dataplatform-iqe` | `dataplatform-preprod` | `dataplatform-prod` |
| Image tag | `1.4.0-dev.42` | `1.4.0-rc.1` | `1.4.0-rc.1` | `1.4.0` | `1.4.0` |
| HPA min / max | 1 / 2 | 1 / 2 | 2 / 4 | 2 / 6 | 3 / 10 |
| Requests (CPU / mem) | 100m / 128Mi | 100m / 128Mi | 250m / 256Mi | 250m / 256Mi | 500m / 512Mi |
| Limits (CPU / mem) | 500m / 512Mi | 500m / 512Mi | 1 / 1Gi | 1 / 1Gi | 2 / 2Gi |
| PDB minAvailable | 1 | 1 | 1 | 1 | 2 |
| Log level | DEBUG | INFO | INFO | INFO | INFO |
| Hostname | `api.dev.…` | `api.ite.…` | `api.iqe.…` | `api.preprod.…` | `api.dataplatform.example.com` |
| cert-manager issuer | staging | staging | staging | prod | prod |
| Key Vault | `kv-dp-data-dev-01` | `kv-dp-data-ite-01` | `kv-dp-data-iqe-01` | `kv-dp-data-preprod-01` | `kv-dp-data-prod-01` |

The Key Vault and storage account names match the Terraform `naming` module, so the manifests and the infrastructure cannot drift apart silently.

## How CI validates

No cluster is needed. The CI workflow runs:

```bash
# Every manifest and patch file validates against the Kubernetes OpenAPI schema;
# CRDs (SecretProviderClass, ServiceMonitor) are skipped rather than failed.
kubeconform -strict -ignore-missing-schemas -summary kubernetes/base kubernetes/overlays/*/

# Each overlay must render, and the rendered output must also validate.
for env in dev ite iqe preprod prod; do
  kubectl kustomize kubernetes/overlays/$env | kubeconform -strict -ignore-missing-schemas -summary
done
```

Locally, `kubectl kustomize kubernetes/overlays/dev | less` shows exactly what would be applied.

## How it deploys from the pipeline

1. **Pipeline identity.** The Azure DevOps service connection uses workload identity federation (OIDC); no service principal secret exists. The pipeline runs `az aks get-credentials` followed by `kubelogin convert-kubeconfig -l azurecli`, so kubectl authenticates with the same federated token.
2. **Apply.** `kubectl apply -k kubernetes/overlays/<env> --prune -l app.kubernetes.io/part-of=dataplatform --server-side`. Pruning removes resources deleted from Git; server-side apply keeps HPA-owned fields out of the diff.
3. **Rollout gate.** `kubectl rollout status deployment/data-api -n dataplatform-<env> --timeout=5m` fails the stage if the new ReplicaSet never becomes ready, which triggers the automatic rollback step.
4. **Pod identity.** The pod's service account is federated with a user-assigned managed identity (`az identity federated-credential create --issuer <AKS OIDC issuer> --subject system:serviceaccount:dataplatform-<env>:data-api`). That identity holds `Key Vault Secrets User` on the environment vault, so the CSI driver mounts secrets with no credential anywhere in the cluster.
5. **Release annotation.** `powershell/azure-devops/New-ReleaseAnnotation.ps1` stamps the deployment onto Application Insights so latency changes can be correlated with releases.

## Design decisions

- **Kustomize over Helm** for first-party workloads: patches are reviewable diffs against a single base, and there is no templating language to debug.
- **HPA owns `replicas`.** The Deployment deliberately omits `spec.replicas`; overlays patch the HPA bounds instead, so a `kubectl apply` never resets a scaled deployment.
- **Secrets never touch Git or the cluster at rest.** The SecretProviderClass pulls from Key Vault at pod start; the mirrored Kubernetes Secret exists only while a pod mounts the volume.
- **Restricted Pod Security** is enforced at the namespace, so a regression in the Deployment's security context is rejected at admission rather than discovered in review.
- **Default-deny network policy** with explicit allows for ingress-nginx, the monitoring namespace, DNS and HTTPS egress. Tightening egress to Azure service tags happens at the Azure Firewall layer, not in-cluster.
- **Patch files repeat `selector`** on the Deployment only so that each patch validates as a standalone document under `kubeconform -strict`.

## Requirements

- AKS 1.29+ with workload identity and OIDC issuer enabled
- Secrets Store CSI driver with the Azure Key Vault provider (`--enable-addons azure-keyvault-secrets-provider`)
- ingress-nginx, cert-manager and kube-prometheus-stack installed cluster-wide
- `kubectl` 1.27+ (bundled kustomize 5.x) and `kubeconform` 0.6+ for local validation
