#!/usr/bin/env bash
# ==============================================================================
# Reset / Cleanup Kubernetes Platform Applications & Controllers
# ==============================================================================
# Cleans up ALL resources deployed via Stages 02, 03, and 04 inside Kubernetes:
#   • Gitea Application, Ingresses, PVCs, PVs, and namespace 'gitea'
#   • ArgoCD GitOps Engine and namespace 'argocd'
#   • AWS Load Balancer Controller and AWS EFS CSI Driver (kube-system)
#   • EFS StorageClass
#
# Leaves AWS Cloud Infrastructure (VPC, EKS Cluster, RDS, EFS, S3, IAM) 100% intact.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "🧹 CLEANING UP KUBERNETES WORKLOADS & CONTROLLERS (Stages 02-04) "
echo "================================================================="
echo "This will reset your Kubernetes cluster while preserving:"
echo "  ✅ Amazon EKS Cluster & Worker Nodes (Untouched)"
echo "  ✅ Amazon RDS PostgreSQL Database   (Untouched)"
echo "  ✅ Amazon EFS File System           (Untouched)"
echo "  ✅ Amazon S3 Storage Bucket         (Untouched)"
echo "  ✅ AWS VPC, Subnets & IAM Roles     (Untouched)"
echo "================================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. Clean Ingresses (Triggers AWS ALB Deletion)
# ------------------------------------------------------------------------------
echo "1. Deleting all Kubernetes Ingresses (triggers AWS ALB release)..."
kubectl delete ingress --all -A --timeout=60s --ignore-not-found=true || true

# ------------------------------------------------------------------------------
# 2. Clean ArgoCD Applications & Finalizers
# ------------------------------------------------------------------------------
echo "2. Stripping finalizers and removing ArgoCD applications..."
for app in $(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
  kubectl patch application "${app}" -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  kubectl delete application "${app}" -n argocd --force --grace-period=0 2>/dev/null || true
done

# ------------------------------------------------------------------------------
# 3. Clean Volumes & PersistentVolumeClaims (Strip Finalizers)
# ------------------------------------------------------------------------------
echo "3. Stripping PVC/PV finalizers and purging volumes..."
kubectl patch pvc --all -n gitea -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
kubectl delete pvc --all -n gitea --force --grace-period=0 2>/dev/null || true
kubectl patch pv --all -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
kubectl delete pv --all --force --grace-period=0 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Uninstall Helm Releases
# ------------------------------------------------------------------------------
echo "4. Uninstalling Helm releases..."
helm uninstall gitea -n gitea 2>/dev/null || true
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
helm uninstall argocd -n argocd 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall aws-efs-csi-driver -n kube-system 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Delete Namespaces & StorageClass
# ------------------------------------------------------------------------------
echo "5. Deleting application namespaces & StorageClass..."
kubectl delete storageclass efs-sc --ignore-not-found=true
kubectl delete namespace gitea argocd monitoring datadog --ignore-not-found=true

echo ""
echo "================================================================="
echo "✅ KUBERNETES RESET COMPLETE: Cluster is clean and ready!        "
echo "================================================================="
echo "You can now run fresh deployments in sequence:"
echo "  1. ./scripts/02-eks-bootstrap.sh"
echo "  2. ./scripts/03-deploy-argocd.sh"
echo "  3. ./scripts/04-deploy-gitea.sh"
echo "================================================================="
