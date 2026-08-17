#!/usr/bin/env bash
# ==============================================================================
# Stage 6: Deploy Datadog APM & Metrics Agent (Optional)
# ==============================================================================
# 1. Checks if DATADOG_ENABLED=true and API Key is provided in env.conf
# 2. Creates datadog-secret in namespace 'datadog'
# 3. Applies datadog-agent Application to ArgoCD
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

DATADOG_ENABLED="${DATADOG_ENABLED:-false}"
DATADOG_SITE="${DATADOG_SITE:-datadoghq.com}"
DATADOG_API_KEY="${DATADOG_API_KEY:-}"
DATADOG_APP_KEY="${DATADOG_APP_KEY:-}"

echo "================================================================="
echo "🐶 STAGE 6: Datadog APM & Metrics Setup                          "
echo "================================================================="

if [ "${DATADOG_ENABLED}" = "true" ] && [ -n "${DATADOG_API_KEY}" ] && [ "${DATADOG_API_KEY}" != "YOUR_DATADOG_API_KEY" ]; then
  echo "1. Configuring Datadog Secret in 'datadog' namespace..."
  kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic datadog-secret \
    --namespace datadog \
    --from-literal=api-key="${DATADOG_API_KEY}" \
    --from-literal=app-key="${DATADOG_APP_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "2. Rendering Datadog Helm values..."
  DD_VALUES=$(sed -e "s|\${DATADOG_SITE}|${DATADOG_SITE}|g" "${ARGOCD_DIR}/values/datadog-values.yaml")

  echo "3. Applying Datadog Agent Application to ArgoCD..."
  python3 -c "
import sys
template = open(sys.argv[1]).read()
values = sys.argv[2]
indented = '\n'.join('        ' + line for line in values.splitlines())
rendered = template.replace(sys.argv[3], indented)
print(rendered)
" "${ARGOCD_DIR}/applications/datadog-app.yaml" "${DD_VALUES}" "__DATADOG_VALUES__" | kubectl apply -f -

  echo ""
  echo "================================================================="
  echo "✅ STAGE 6 COMPLETE: Datadog Agent Registered in ArgoCD!        "
  echo "================================================================="
  echo "Status:   kubectl get daemonset -n datadog"
  echo "================================================================="
else
  echo "ℹ️ Datadog is currently disabled (DATADOG_ENABLED=${DATADOG_ENABLED})."
  echo "   To enable Datadog later, add your API key in argocd/env.conf and run:"
  echo "   ./scripts/06-deploy-datadog.sh"
  echo "================================================================="
fi
