# Kubernetes Manifests

AKS (Azure Kubernetes Service) deployment manifests for containerised data platform services. Includes deployments, services, config maps, ingress and autoscaling configurations.

| Manifest | Purpose |
|----------|---------|
| `namespace.yml` | Namespace isolation with resource quotas and network policies |
| `api-deployment.yml` | Data API deployment with health checks, resource limits and rolling updates |
| `configmap-secrets.yml` | ConfigMap for app settings and ExternalSecret for Key Vault integration |
| `ingress.yml` | Nginx ingress with TLS termination and path-based routing |
| `autoscaling-monitoring.yml` | HPA, PodDisruptionBudget and ServiceMonitor for Prometheus |

## Usage

```bash
kubectl apply -f kubernetes/ -n data-platform
kubectl get pods -n data-platform
kubectl get hpa -n data-platform
```

## Requirements

- AKS cluster with RBAC enabled
- Azure Key Vault CSI driver (for secret injection)
- Nginx Ingress Controller
- cert-manager (for TLS certificates)
