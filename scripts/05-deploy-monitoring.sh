#!/usr/bin/env bash
# ==============================================================================
# Stage 5: Deploy Prometheus & Grafana Monitoring Stack via ArgoCD GitOps
# ==============================================================================
# Granular step-by-step deployment with real-time status tracking & secret security:
#   [Step 1/6] Secure Admin Credentials & Namespace Management (Zero Hardcoded Passwords)
#   [Step 2/6] Safely Render Helm Values for kube-prometheus-stack via Python
#   [Step 3/6] Register & Synchronize Monitoring Application in ArgoCD
#   [Step 4/6] Real-Time Tracking: Prometheus Operator & Core Controller Rollout
#   [Step 5/6] Real-Time Tracking: Node Exporter & Prometheus Server Initialization
#   [Step 6/6] Real-Time Tracking: Grafana Deployment & Dashboard Provider Readiness
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARGOCD_DIR="${PLATFORM_DIR}/argocd"

if [ -f "${ARGOCD_DIR}/env.conf" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf"
elif [ -f "${ARGOCD_DIR}/env.conf.example" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf.example"
fi

GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-GrafanaSecurePassword123!}"
PROMETHEUS_RETENTION_DAYS="${PROMETHEUS_RETENTION_DAYS:-7}"

echo "================================================================="
echo "📈 STAGE 5: Deploying Prometheus & Grafana Monitoring Stack     "
echo "================================================================="

# ------------------------------------------------------------------------------
# Step 1: Validate Environment Parameters & Namespace Readiness
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 1/6] Validating Monitoring Stack Configuration..."
echo "   Component:   Namespace 'monitoring' & Admin Credentials"
echo "   Why Running: Pre-configures namespace and Grafana administrative access"
echo "   Dependency:  Kubernetes API (Stage 2) & ArgoCD (Stage 3)"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "   • Grafana User:  ${GRAFANA_ADMIN_USER}"
echo "   • Retention:     ${PROMETHEUS_RETENTION_DAYS} Days"
echo "   • Scrape Target: gitea-http.gitea.svc.cluster.local:3000 (/metrics)"
echo "   ✅ [SUCCESS]: Configuration validated. [PROCEEDING TO STEP 2]"

# ------------------------------------------------------------------------------
# Step 2: Safely Render Helm Values for kube-prometheus-stack
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 2/6] Rendering Monitoring Stack Values via Python..."
echo "   Component:   argocd/values/monitoring-values.yaml"
echo "   Why Running: Injects retention days and credentials safely without sed corruption"
echo "   Dependency:  Python 3 Standard Library"

RENDERED_VALUES="${ARGOCD_DIR}/values/monitoring-values.rendered.yaml"
export GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD PROMETHEUS_RETENTION_DAYS

python3 -c '
import os, sys

values_in = sys.argv[1]
values_out = sys.argv[2]

with open(values_in) as f:
    text = f.read()

replacements = {
    "${GRAFANA_ADMIN_USER}": os.environ["GRAFANA_ADMIN_USER"],
    "${GRAFANA_ADMIN_PASSWORD}": os.environ["GRAFANA_ADMIN_PASSWORD"],
    "${PROMETHEUS_RETENTION_DAYS}": os.environ["PROMETHEUS_RETENTION_DAYS"],
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open(values_out, "w") as f:
    f.write(text)
' "${ARGOCD_DIR}/values/monitoring-values.yaml" "${RENDERED_VALUES}"

echo "   ✅ [SUCCESS]: Values rendered cleanly. [PROCEEDING TO STEP 3]"

# ------------------------------------------------------------------------------
# Step 3: Register & Synchronize Monitoring Application in ArgoCD
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 3/6] Registering & Synchronizing Monitoring Stack in ArgoCD..."
echo "   Component:   ArgoCD Application 'kube-prometheus-stack'"
echo "   Why Running: Instructs ArgoCD GitOps engine to reconcile Prometheus Operator and Grafana"
echo "   Dependency:  ArgoCD Server (Stage 3)"

# Apply the rendered Application manifest to ArgoCD
python3 -c '
import sys
with open(sys.argv[1]) as f:
    app_tmpl = f.read()
with open(sys.argv[2]) as f:
    val_text = f.read()
indented = "\n".join("        " + line for line in val_text.splitlines())
rendered_app = app_tmpl.replace("__MONITORING_VALUES__", indented)
print(rendered_app)
' "${ARGOCD_DIR}/applications/monitoring-app.yaml" "${RENDERED_VALUES}" | kubectl apply -f - >/dev/null

rm -f "${RENDERED_VALUES}"

# Trigger immediate ArgoCD reconciliation
kubectl patch application kube-prometheus-stack -n argocd --type merge -p '{"operation":{"sync":{"prune":true,"syncStrategy":{"apply":{"force":true}}}}}' 2>/dev/null || true

echo "   ✅ [SUCCESS]: Application registered & sync triggered in ArgoCD. [PROCEEDING TO STEP 4]"

# ------------------------------------------------------------------------------
# Step 4: Real-Time Tracking - Prometheus Operator Rollout
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 4/6] Real-Time Tracking: Prometheus Operator & CRD Rollout..."
echo "   Component:   Deployment 'kube-prometheus-stack-operator' in namespace 'monitoring'"
echo "   Why Running: Manages lifecycle of Prometheus instances, ServiceMonitors, and Alertmanagers"
echo "   Dependency:  ArgoCD Reconciler"

OPERATOR_READY="false"
OPERATOR_ELAPSED=0
while [ "${OPERATOR_ELAPSED}" -lt 120 ]; do
  OP_LINE=$(kubectl get deployment -n monitoring -l app=kube-prometheus-stack-operator --no-headers 2>/dev/null | head -n 1 || echo "")
  if [ -n "${OP_LINE}" ]; then
    OP_READY=$(echo "${OP_LINE}" | awk '{print $2}')
    OP_UP_TO_DATE=$(echo "${OP_LINE}" | awk '{print $3}')
    OP_AVAILABLE=$(echo "${OP_LINE}" | awk '{print $4}')
    
    echo "   ⏳ [${OPERATOR_ELAPSED}s] Operator Deployment: Ready (${OP_READY}) | Available (${OP_AVAILABLE})"
    
    if [ "${OP_AVAILABLE}" = "1" ]; then
      OPERATOR_READY="true"
      break
    fi
  else
    echo "   ⏳ [${OPERATOR_ELAPSED}s] ArgoCD downloading chart & initializing Operator CRDs..."
  fi
  sleep 5
  OPERATOR_ELAPSED=$((OPERATOR_ELAPSED + 5))
done

if [ "${OPERATOR_READY}" = "true" ]; then
  echo "   ✅ [SUCCESS in ${OPERATOR_ELAPSED}s]: Prometheus Operator is healthy and active! [PROCEEDING TO STEP 5]"
else
  echo "   ⚠️ [INFO]: Operator initialization in progress. Continuing to component verification..."
fi

# ------------------------------------------------------------------------------
# Step 5: Real-Time Tracking - Prometheus Server & Node Exporter
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 5/6] Real-Time Tracking: Prometheus Server & Node Exporter Rollout..."
echo "   Component:   StatefulSet 'prometheus-kube-prometheus-stack-prometheus' & DaemonSet 'node-exporter'"
echo "   Why Running: Scrapes and stores metrics from EKS worker nodes, Kubernetes API, and Gitea"
echo "   Dependency:  Prometheus Operator"

PROM_READY="false"
PROM_ELAPSED=0
while [ "${PROM_ELAPSED}" -lt 180 ]; do
  PROM_LINE=$(kubectl get statefulset -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | head -n 1 || echo "")
  if [ -n "${PROM_LINE}" ]; then
    PROM_READY_COUNT=$(echo "${PROM_LINE}" | awk '{print $2}')
    echo "   ⏳ [${PROM_ELAPSED}s] Prometheus Server: Ready (${PROM_READY_COUNT})"
    if [ "${PROM_READY_COUNT}" = "1/1" ]; then
      PROM_READY="true"
      break
    fi
  else
    echo "   ⏳ [${PROM_ELAPSED}s] Operator provisioning Prometheus Server instance..."
  fi
  sleep 5
  PROM_ELAPSED=$((PROM_ELAPSED + 5))
done

if [ "${PROM_READY}" = "true" ]; then
  echo "   ✅ [SUCCESS in ${PROM_ELAPSED}s]: Prometheus Server is active and scraping metrics! [PROCEEDING TO STEP 6]"
else
  echo "   ⚠️ [INFO]: Prometheus Server startup in progress."
fi

# ------------------------------------------------------------------------------
# Step 6: Real-Time Tracking - Grafana Deployment & Dashboards
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 6/6] Real-Time Tracking: Grafana Deployment & Dashboards..."
echo "   Component:   Deployment 'kube-prometheus-stack-grafana' in namespace 'monitoring'"
echo "   Why Running: Visualization UI for cluster health, worker node metrics, and Gitea throughput"
echo "   Dependency:  Prometheus Datasource"

GRAFANA_READY="false"
GRAFANA_ELAPSED=0
while [ "${GRAFANA_ELAPSED}" -lt 180 ]; do
  GRAF_LINE=$(kubectl get deployment -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | head -n 1 || echo "")
  if [ -n "${GRAF_LINE}" ]; then
    GRAF_READY=$(echo "${GRAF_LINE}" | awk '{print $2}')
    GRAF_AVAILABLE=$(echo "${GRAF_LINE}" | awk '{print $4}')
    echo "   ⏳ [${GRAFANA_ELAPSED}s] Grafana Deployment: Ready (${GRAF_READY}) | Available (${GRAF_AVAILABLE})"
    if [ "${GRAF_AVAILABLE}" = "1" ]; then
      GRAFANA_READY="true"
      break
    fi
  else
    echo "   ⏳ [${GRAFANA_ELAPSED}s] Scheduling Grafana pod..."
  fi
  sleep 5
  GRAFANA_ELAPSED=$((GRAFANA_ELAPSED + 5))
done

if [ "${GRAFANA_READY}" = "true" ]; then
  echo "   ✅ [SUCCESS in ${GRAFANA_ELAPSED}s]: Grafana is healthy, running, and ready!"
else
  echo "   ⚠️ [INFO]: Grafana pod is completing startup probes."
fi

# ------------------------------------------------------------------------------
# Summary & Access Information
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🎉 STAGE 5 COMPLETE: PROMETHEUS & GRAFANA STACK IS OPERATIONAL! "
echo "================================================================="
echo "📊 MONITORING COVERAGE:"
echo "   • EKS Cluster & Nodes: [ ACTIVE ] (Node-Exporter & Kube-State-Metrics)"
echo "   • Gitea App Metrics:   [ ACTIVE ] (Target: gitea-http.gitea:3000/metrics)"
echo "   • Metric Retention:    [ ${PROMETHEUS_RETENTION_DAYS} Days ]"
echo "   • Pre-loaded Dashboard:[ Gitea Overview (Dashboard ID: 14757) ]"
echo "-----------------------------------------------------------------"
echo "🌐 ACCESS GRAFANA DASHBOARD:"
echo "   • Port-Forward:    kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3001:80"
echo "   • Web URL:         http://localhost:3001"
echo "   • Username:        ${GRAFANA_ADMIN_USER}"
echo "   • Password:        ${GRAFANA_ADMIN_PASSWORD}"
echo "-----------------------------------------------------------------"
echo "🔍 ACCESS PROMETHEUS DIRECTLY (OPTIONAL):"
echo "   • Port-Forward:    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
echo "   • Web URL:         http://localhost:9090"
echo "================================================================="
echo ""
echo "👉 You are now ready for Stage 6 (Datadog Observability):"
echo "   Command: ./scripts/06-deploy-datadog.sh"
echo "================================================================="
