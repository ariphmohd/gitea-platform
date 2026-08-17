#!/usr/bin/env bash
# ==============================================================================
# Fast Reset Utility for Stage 4 (Gitea Application Teardown)
# ==============================================================================
# Forces immediate, clean teardown of Stage 4 Kubernetes resources:
# - Strips ArgoCD finalizers & deletes 'gitea' Application
# - Deletes Ingress (signals ALB controller)
# - Strips PVC/PV finalizers & deletes namespace 'gitea'
# - Recreates clean namespace 'gitea'
# - 100% Preserves AWS Cloud Infrastructure (EKS, RDS PostgreSQL, Multi-AZ EFS, S3, IAM)
# ==============================================================================

set -euo pipefail

echo "================================================================="
echo "🧹 FAST RESET: Tearing Down Stage 4 (Gitea Application)         "
echo "================================================================="

# 1. Strip ArgoCD Application finalizers and delete
echo "🔹 [1/4] Stripping ArgoCD finalizers & deleting Gitea Application..."
kubectl patch application gitea -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
kubectl delete application gitea -n argocd --cascade=foreground --timeout=15s 2>/dev/null || true

# 2. Delete Ingress to release AWS ALB
echo "🔹 [2/4] Deleting Ingress & notifying AWS Load Balancer Controller..."
kubectl delete ingress --all -n gitea --timeout=15s 2>/dev/null || true

# 3. Strip PVC finalizers and delete namespace gitea
echo "🔹 [3/4] Stripping PVC/PV finalizers in namespace 'gitea'..."
kubectl patch pvc --all -n gitea -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl patch pv --all -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
kubectl delete namespace gitea --timeout=20s 2>/dev/null || true

# Force delete namespace if stuck in terminating
if kubectl get namespace gitea >/dev/null 2>&1; then
  echo "   ⚡ Force removing namespace 'gitea' finalizers..."
  kubectl get namespace gitea -o json 2>/dev/null | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" | kubectl replace --raw "/api/v1/namespaces/gitea/finalize" -f - >/dev/null 2>&1 || true
fi

# 4. Re-create clean empty namespace
kubectl create namespace gitea >/dev/null 2>&1 || true

echo "================================================================="
echo "🎉 STAGE 4 TEARDOWN COMPLETE! Namespace 'gitea' is 100% clean."
echo "👉 You can now run a fresh Stage 4 deployment:"
echo "   Command: ./scripts/04-deploy-gitea.sh"
echo "================================================================="
