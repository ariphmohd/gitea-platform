#!/usr/bin/env bash
# ==============================================================================
# Gitea Platform - Master Deployment Orchestrator
# Executes Stage 01 through Stage 06 sequentially with live status output
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "🚀 STARTING FULL GITEA PLATFORM DEPLOYMENT (Stages 01 -> 06)     "
echo "================================================================="

# Execute Stages Sequentially
"${SCRIPT_DIR}/01-infra-terraform.sh"
"${SCRIPT_DIR}/02-eks-bootstrap.sh"
"${SCRIPT_DIR}/03-deploy-argocd.sh"
"${SCRIPT_DIR}/04-deploy-gitea.sh"
"${SCRIPT_DIR}/05-deploy-monitoring.sh"
"${SCRIPT_DIR}/06-deploy-datadog.sh"

echo ""
echo "================================================================="
echo "🎉 ALL STAGES COMPLETE! FULL PLATFORM IS RUNNING                "
echo "================================================================="
echo ""
echo "📊 CONSOLIDATED DASHBOARDS & ACCESS DETAILS:"
echo "-----------------------------------------------------------------"
echo "1. 🐙 ArgoCD GitOps Dashboard:"
echo "   Port-Forward:   kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "   URL:            http://localhost:8080"
echo "   Username:       admin"
echo "   Get Password:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo "2. ☕ Gitea Web UI:"
echo "   Port-Forward:   kubectl port-forward svc/gitea-http -n gitea 3000:3000"
echo "   URL:            http://localhost:3000"
echo "   AWS ALB Ingress: kubectl get ingress -n gitea"
echo ""
echo "3. 📈 Grafana Monitoring Dashboard:"
echo "   Port-Forward:   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3001:80"
echo "   URL:            http://localhost:3001"
echo "   Username:       admin"
echo "   Password:       GrafanaSecurePassword123!"
echo "================================================================="
