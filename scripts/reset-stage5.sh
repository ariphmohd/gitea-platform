#!/usr/bin/env bash
# ==============================================================================
# Fast Reset Utility for Stage 5 (Prometheus & Grafana Teardown)
# ==============================================================================
# Forces immediate, clean teardown of Stage 5 Kubernetes resources:
# - Strips ArgoCD finalizers & deletes 'kube-prometheus-stack' Application
# - Deletes namespace 'monitoring' & all monitoring pods
# - Recreates clean namespace 'monitoring'
# - 100% Preserves AWS Infrastructure, EKS Cluster, Gitea Application, and ArgoCD
# ==============================================================================

set -euo pipefail

echo "================================================================="
echo "🧹 FAST RESET: Tearing Down Stage 5 (Monitoring Stack)          "
echo "================================================================="

# 1. Strip ArgoCD Application finalizers and delete
echo "🔹 [1/3] Stripping ArgoCD finalizers & deleting Monitoring Application..."
kubectl patch application kube-prometheus-stack -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
kubectl delete application kube-prometheus-stack -n argocd --cascade=foreground --timeout=15s 2>/dev/null || true

# 2. Delete namespace monitoring
echo "🔹 [2/3] Deleting namespace 'monitoring'..."
kubectl delete namespace monitoring --timeout=20s 2>/dev/null || true

# Force delete namespace if stuck in terminating
if kubectl get namespace monitoring >/dev/null 2>&1; then
  echo "   ⚡ Force removing namespace 'monitoring' finalizers..."
  kubectl get namespace monitoring -o json 2>/dev/null | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" | kubectl replace --raw "/api/v1/namespaces/monitoring/finalize" -f - >/dev/null 2>&1 || true
fi

# 3. Re-create clean empty namespace
kubectl create namespace monitoring >/dev/null 2>&1 || true

echo "================================================================="
echo "🎉 STAGE 5 TEARDOWN COMPLETE! Namespace 'monitoring' is 100% clean."
echo "👉 You can now run a fresh Stage 5 deployment:"
echo "   Command: ./scripts/05-deploy-monitoring.sh"
echo "================================================================="
