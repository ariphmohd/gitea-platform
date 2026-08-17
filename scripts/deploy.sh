#!/usr/bin/env bash
# ==============================================================================
# Gitea Platform - Automated Modular Deployment with ArgoCD & Monitoring
# AWS Region: ap-south-1 (Mumbai)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PLATFORM_DIR}/terraform"
ARGOCD_DIR="${PLATFORM_DIR}/argocd"
K8S_DIR="${PLATFORM_DIR}/k8s"

# ------------------------------------------------------------------------------
# 1. Load Central Configuration
# ------------------------------------------------------------------------------
if [ -f "${ARGOCD_DIR}/env.conf" ]; then
  echo "📄 Loading configuration from argocd/env.conf..."
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf"
elif [ -f "${ARGOCD_DIR}/env.conf.example" ]; then
  echo "ℹ️ No env.conf found. Loading defaults from argocd/env.conf.example..."
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf.example"
fi

AWS_REGION="${AWS_REGION:-ap-south-1}"
GITEA_DOMAIN="${GITEA_DOMAIN:-git.local}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-GrafanaSecurePassword123!}"
DATADOG_ENABLED="${DATADOG_ENABLED:-false}"
DATADOG_SITE="${DATADOG_SITE:-datadoghq.com}"
DATADOG_API_KEY="${DATADOG_API_KEY:-}"
DATADOG_APP_KEY="${DATADOG_APP_KEY:-}"
PROMETHEUS_RETENTION_DAYS="${PROMETHEUS_RETENTION_DAYS:-7}"

echo "================================================================="
echo "   Deploying Gitea Platform & Observability Stack (${AWS_REGION}) "
echo "================================================================="

# ------------------------------------------------------------------------------
# 2. Prerequisite Checks
# ------------------------------------------------------------------------------
command -v terraform >/dev/null 2>&1 || { echo "❌ Error: terraform is required."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "❌ Error: aws-cli is required."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ Error: kubectl is required."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Error: helm is required."; exit 1; }

echo "✅ Prerequisites verified."

# ------------------------------------------------------------------------------
# 3. AWS Authentication
# ------------------------------------------------------------------------------
echo "🔍 Checking AWS authentication in region ${AWS_REGION}..."
aws sts get-caller-identity >/dev/null || { echo "❌ Error: AWS auth failed. Configure credentials."; exit 1; }
echo "✅ AWS credentials verified."

# ------------------------------------------------------------------------------
# 4. Terraform Infrastructure Provisioning
# ------------------------------------------------------------------------------
echo "🚀 Applying Terraform Infrastructure..."
cd "${TERRAFORM_DIR}"

if [ ! -f "terraform.tfvars" ]; then
  if [ -f "terraform.tfvars.example" ]; then
    echo "ℹ️ No terraform.tfvars found. Creating automatically from terraform.tfvars.example..."
    cp terraform.tfvars.example terraform.tfvars
  fi
fi

terraform init
terraform state rm 'helm_release.argocd[0]' helm_release.aws_efs_csi_driver helm_release.aws_load_balancer_controller 2>/dev/null || true
terraform validate
terraform apply -auto-approve

# ------------------------------------------------------------------------------
# 5. Retrieve Infrastructure Outputs
# ------------------------------------------------------------------------------
echo "📥 Fetching infrastructure parameters..."
CLUSTER_NAME=$(terraform output -raw cluster_name)
VPC_ID=$(terraform output -raw vpc_id)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn)
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
EFS_ID=$(terraform output -raw efs_file_system_id)
GITEA_IRSA_ROLE_ARN=$(terraform output -raw gitea_irsa_role_arn)
ALB_CONTROLLER_IRSA_ROLE_ARN=$(terraform output -raw alb_controller_irsa_role_arn)
EFS_CSI_IRSA_ROLE_ARN=$(terraform output -raw efs_csi_irsa_role_arn)

echo "-----------------------------------------------------------------"
echo "Cluster:        ${CLUSTER_NAME}"
echo "RDS Host:       ${RDS_ENDPOINT}"
echo "S3 Bucket:      ${S3_BUCKET_NAME}"
echo "EFS ID:         ${EFS_ID}"
echo "Gitea IRSA:     ${GITEA_IRSA_ROLE_ARN}"
echo "-----------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 6. Configure Kubeconfig & Namespaces
# ------------------------------------------------------------------------------
echo "🔌 Updating kubeconfig..."
aws eks --region "${AWS_REGION}" update-kubeconfig --name "${CLUSTER_NAME}"

echo "📁 Ensuring required namespaces exist..."
for ns in argocd gitea monitoring datadog kube-system; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

# ------------------------------------------------------------------------------
# 7. Apply StorageClass for EFS
# ------------------------------------------------------------------------------
echo "💾 Configuring EFS StorageClass..."
sed "s/__EFS_FILE_SYSTEM_ID__/${EFS_ID}/g" "${K8S_DIR}/efs-storageclass.yaml" | kubectl apply -f -

# ------------------------------------------------------------------------------
# 8. Install / Upgrade AWS Core Controllers via Helm
# ------------------------------------------------------------------------------
echo "📦 Adding Helm Repositories..."
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/ >/dev/null 2>&1 || true
helm repo add argo-helm https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null 2>&1 || true
helm repo update

echo "🚀 Deploying AWS Load Balancer Controller..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${ALB_CONTROLLER_IRSA_ROLE_ARN}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set enableServiceMutatorWebhook=false

echo "🚀 Deploying AWS EFS CSI Driver..."
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=efs-csi-controller-sa \
  --set controller.serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${EFS_CSI_IRSA_ROLE_ARN}"

# ------------------------------------------------------------------------------
# 9. Deploy ArgoCD (GitOps Engine)
# ------------------------------------------------------------------------------
echo "🐙 Deploying ArgoCD..."
kubectl delete job --all -n argocd --ignore-not-found=true

helm upgrade --install argocd argo-helm/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=ClusterIP \
  --set configs.params.server\\.insecure=true \
  --no-hooks

# ------------------------------------------------------------------------------
# 10. Retrieve Database Password & Generate Security Tokens
# ------------------------------------------------------------------------------
echo "🔐 Fetching database password from AWS Secrets Manager..."
DB_SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${RDS_SECRET_ARN}" --region "${AWS_REGION}" --query SecretString --output text)
RDS_PASSWORD=$(echo "${DB_SECRET_JSON}" | grep -o '"password":"[^"]*' | cut -d'"' -f4)

GITEA_SECRET_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
GITEA_INTERNAL_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# ------------------------------------------------------------------------------
# 11. Configure Datadog Secret (if enabled)
# ------------------------------------------------------------------------------
if [ "${DATADOG_ENABLED}" = "true" ] && [ -n "${DATADOG_API_KEY}" ] && [ "${DATADOG_API_KEY}" != "YOUR_DATADOG_API_KEY" ]; then
  echo "🐶 Configuring Datadog Secret in 'datadog' namespace..."
  kubectl create secret generic datadog-secret \
    --namespace datadog \
    --from-literal=api-key="${DATADOG_API_KEY}" \
    --from-literal=app-key="${DATADOG_APP_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "ℹ️ Datadog is disabled (DATADOG_ENABLED=${DATADOG_ENABLED}). Skipping Datadog secret creation."
fi

# ------------------------------------------------------------------------------
# 12. Wait for ArgoCD Ready State & Fetch Password
# ------------------------------------------------------------------------------
echo "⏳ Waiting for ArgoCD Server to initialize..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || true

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "admin")

# ------------------------------------------------------------------------------
# 13. Deploy ArgoCD GitOps Applications
# ------------------------------------------------------------------------------
echo "🐙 Deploying ArgoCD Applications..."

render_and_apply_app() {
  local template_file="$1"
  local values_content="$2"
  local placeholder="$3"

  python3 -c "
import sys
template = open(sys.argv[1]).read()
values = sys.argv[2]
indented = '\n'.join('        ' + line for line in values.splitlines())
rendered = template.replace(sys.argv[3], indented)
print(rendered)
" "${template_file}" "${values_content}" "${placeholder}" | kubectl apply -f -
}

# 13a. Deploy Prometheus & Grafana Stack
echo "  -> Deploying Monitoring Stack (Prometheus & Grafana)..."
MON_VALUES=$(sed \
  -e "s|\${GRAFANA_ADMIN_USER}|${GRAFANA_ADMIN_USER}|g" \
  -e "s|\${GRAFANA_ADMIN_PASSWORD}|${GRAFANA_ADMIN_PASSWORD}|g" \
  -e "s|\${PROMETHEUS_RETENTION_DAYS}|${PROMETHEUS_RETENTION_DAYS}|g" \
  "${ARGOCD_DIR}/values/monitoring-values.yaml")
render_and_apply_app "${ARGOCD_DIR}/applications/monitoring-app.yaml" "${MON_VALUES}" "__MONITORING_VALUES__"

# 13b. Deploy Gitea Application
echo "  -> Deploying Gitea Application..."
GITEA_VALUES=$(sed \
  -e "s|\${GITEA_DOMAIN}|${GITEA_DOMAIN}|g" \
  -e "s|\${RDS_ENDPOINT}|${RDS_ENDPOINT}|g" \
  -e "s|\${RDS_PASSWORD}|${RDS_PASSWORD}|g" \
  -e "s|\${S3_BUCKET_NAME}|${S3_BUCKET_NAME}|g" \
  -e "s|\${GITEA_IRSA_ROLE_ARN}|${GITEA_IRSA_ROLE_ARN}|g" \
  -e "s|\${GITEA_SECRET_KEY}|${GITEA_SECRET_KEY}|g" \
  -e "s|\${GITEA_INTERNAL_TOKEN}|${GITEA_INTERNAL_TOKEN}|g" \
  "${ARGOCD_DIR}/values/gitea-values.yaml")
render_and_apply_app "${ARGOCD_DIR}/applications/gitea-app.yaml" "${GITEA_VALUES}" "__GITEA_VALUES__"

# 13c. Deploy Datadog Agent (if enabled)
if [ "${DATADOG_ENABLED}" = "true" ] && [ -n "${DATADOG_API_KEY}" ] && [ "${DATADOG_API_KEY}" != "YOUR_DATADOG_API_KEY" ]; then
  echo "  -> Deploying Datadog Agent..."
  DD_VALUES=$(sed -e "s|\${DATADOG_SITE}|${DATADOG_SITE}|g" "${ARGOCD_DIR}/values/datadog-values.yaml")
  render_and_apply_app "${ARGOCD_DIR}/applications/datadog-app.yaml" "${DD_VALUES}" "__DATADOG_VALUES__"
else
  echo "ℹ️ Datadog is not enabled. Skipping Datadog agent deployment (No errors)."
fi

# ------------------------------------------------------------------------------
# 14. Print Summary and Dashboard Access Details
# ------------------------------------------------------------------------------
echo "================================================================="
echo "🎉 DEPLOYMENT COMPLETE! All applications registered in ArgoCD."
echo "================================================================="
echo ""
echo "📊 ACCESS DASHBOARDS & CREDENTIALS:"
echo "-----------------------------------------------------------------"
echo "1. 🐙 ArgoCD GitOps Dashboard:"
echo "   Port-Forward:   kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "   URL:            http://localhost:8080"
echo "   Username:       admin"
echo "   Password:       ${ARGOCD_PASSWORD}"
echo ""
echo "2. 📈 Grafana Monitoring Dashboard:"
echo "   Port-Forward:   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3001:80"
echo "   URL:            http://localhost:3001"
echo "   Username:       ${GRAFANA_ADMIN_USER}"
echo "   Password:       ${GRAFANA_ADMIN_PASSWORD}"
echo ""
echo "3. ☕ Gitea Web UI:"
echo "   Port-Forward:   kubectl port-forward svc/gitea-http -n gitea 3000:3000"
echo "   URL:            http://localhost:3000"
echo "   Check Ingress:  kubectl get ingress -n gitea"
echo ""
if [ "${DATADOG_ENABLED}" = "true" ] && [ -n "${DATADOG_API_KEY}" ]; then
echo "4. 🐶 Datadog APM & Metrics:"
echo "   Status:         kubectl get daemonset -n datadog"
echo "   Check Agent:    kubectl exec -it -n datadog \$(kubectl get pods -n datadog -l app.kubernetes.io/name=datadog -o jsonpath='{.items[0].metadata.name}') -c agent -- agent status"
echo ""
fi
echo "================================================================="
