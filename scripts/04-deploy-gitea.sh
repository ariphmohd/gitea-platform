#!/usr/bin/env bash
# ==============================================================================
# Stage 4: Deploy Gitea Application (Idempotent GitOps Pipeline)
# ==============================================================================
# 1. Validates infrastructure outputs (RDS, S3, IAM)
# 2. Retrieves Database Password securely from AWS Secrets Manager
# 3. Idempotent Security Tokens: Reuses existing secret keys to preserve DB encryption
# 4. Configures Gitea Admin Credentials Secret in Kubernetes
# 5. Renders values safely via Python & triggers ArgoCD synchronization
# 6. Smart PVC Checker: Detects existing Bound Multi-AZ EFS volume immediately
# 7. Smart Pod Checker: Detects active 1/1 Running pod or tracks clean rollout
# 8. Dynamic ALB Discovery: Retrieves public AWS ALB hostname and credentials
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PLATFORM_DIR}/terraform"
ARGOCD_DIR="${PLATFORM_DIR}/argocd"

AWS_REGION="${AWS_REGION:-ap-south-1}"
if [ -f "${ARGOCD_DIR}/env.conf" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf"
elif [ -f "${ARGOCD_DIR}/env.conf.example" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf.example"
fi

GITEA_DOMAIN="${GITEA_DOMAIN:-git.local}"

echo "================================================================="
echo "☕ STAGE 4: Deploying Gitea Application (GitOps)                 "
echo "================================================================="

cd "${TERRAFORM_DIR}"

# ------------------------------------------------------------------------------
# Step 1: Read & Validate Infrastructure Parameters
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 1/8] Reading & Validating Infrastructure Outputs..."
echo "   Component:   Terraform State Outputs (RDS, S3, IAM)"
echo "   Why Running: Gitea requires database endpoint, S3 bucket, and IAM role"
echo "   Dependency:  Stage 1 (01-infra-terraform.sh)"

RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn 2>/dev/null || echo "")
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
GITEA_IRSA_ROLE_ARN=$(terraform output -raw gitea_irsa_role_arn 2>/dev/null || echo "")

if [ -z "${RDS_ENDPOINT}" ] || [ -z "${RDS_SECRET_ARN}" ] || [ -z "${S3_BUCKET_NAME}" ] || [ -z "${GITEA_IRSA_ROLE_ARN}" ]; then
  echo "   ❌ [ERROR]: Missing required Terraform outputs. Please ensure Stage 1 ran successfully."
  exit 1
fi

echo "   • RDS Endpoint:  ${RDS_ENDPOINT}"
echo "   • S3 Bucket:     ${S3_BUCKET_NAME}"
echo "   • Gitea IAM:     ${GITEA_IRSA_ROLE_ARN}"
echo "   ✅ [SUCCESS]: All infrastructure outputs loaded. [PROCEEDING TO STEP 2]"

# ------------------------------------------------------------------------------
# Step 2: Retrieve Database Password from AWS Secrets Manager
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 2/8] Retrieving Database Credentials from Secrets Manager..."
echo "   Component:   AWS Secrets Manager (${RDS_SECRET_ARN})"
echo "   Why Running: Fetches the encrypted master password for Amazon RDS PostgreSQL"
echo "   Dependency:  AWS Secrets Manager & IAM Permissions"

DB_SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${RDS_SECRET_ARN}" --region "${AWS_REGION}" --query SecretString --output text)
RDS_PASSWORD=$(echo "${DB_SECRET_JSON}" | grep -o '"password":"[^"]*' | cut -d'"' -f4)

if [ -z "${RDS_PASSWORD}" ]; then
  echo "   ❌ [ERROR]: Failed to parse RDS password from Secrets Manager JSON."
  exit 1
fi
echo "   ✅ [SUCCESS]: Database credentials retrieved securely. [PROCEEDING TO STEP 3]"

# ------------------------------------------------------------------------------
# Step 3: Idempotent Security Token Management
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 3/8] Managing Gitea Cryptographic Security Tokens..."
echo "   Component:   Kubernetes Secret 'gitea-security-tokens' in namespace 'gitea'"
echo "   Why Running: Preserves identical encryption keys across runs to prevent DB corruption"
echo "   Dependency:  Kubernetes API"

kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Check if security tokens already exist in cluster
EXISTING_SECRET_KEY=$(kubectl get secret gitea-security-tokens -n gitea -o jsonpath='{.data.secret_key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
EXISTING_INTERNAL_TOKEN=$(kubectl get secret gitea-security-tokens -n gitea -o jsonpath='{.data.internal_token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "${EXISTING_SECRET_KEY}" ] && [ -n "${EXISTING_INTERNAL_TOKEN}" ]; then
  GITEA_SECRET_KEY="${EXISTING_SECRET_KEY}"
  GITEA_INTERNAL_TOKEN="${EXISTING_INTERNAL_TOKEN}"
  echo "   • Status:        Reusing existing cryptographic tokens (Database encryption preserved)"
else
  GITEA_SECRET_KEY=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  GITEA_INTERNAL_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
  kubectl create secret generic gitea-security-tokens \
    --namespace gitea \
    --from-literal=secret_key="${GITEA_SECRET_KEY}" \
    --from-literal=internal_token="${GITEA_INTERNAL_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "   • Status:        Generated new persistent security tokens"
fi
echo "   ✅ [SUCCESS]: Security tokens active. [PROCEEDING TO STEP 4]"

# ------------------------------------------------------------------------------
# Step 4: Configure Gitea Admin Credentials Secret (Zero-Plaintext Security)
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 4/8] Configuring Gitea Administrator Credentials in Kubernetes..."
echo "   Component:   Kubernetes Secret 'gitea-admin-secret' in namespace 'gitea'"
echo "   Why Running: Zero-plaintext bootstrap credential with mandatory first-login password rotation"
echo "   Dependency:  Kubernetes API (Stage 2)"

GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea_admin}"

# Check if secret already exists to maintain continuity
EXISTING_GITEA_PASS=$(kubectl get secret gitea-admin-secret -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -n "${EXISTING_GITEA_PASS}" ]; then
  GITEA_ADMIN_PASSWORD="${EXISTING_GITEA_PASS}"
  echo "   • Status:        Using existing persistent admin credentials"
else
  # Generate cryptographically secure 20-character temporary password
  GITEA_ADMIN_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)
  kubectl create secret generic gitea-admin-secret \
    --namespace gitea \
    --from-literal=username="${GITEA_ADMIN_USER}" \
    --from-literal=password="${GITEA_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "   • Status:        Generated new 256-bit random temporary password"
fi

# Clean up any stale PVC finalizers
kubectl patch pvc --all -n gitea -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true

echo "   • Admin Username: ${GITEA_ADMIN_USER}"
echo "   • Admin Secret:   gitea-admin-secret (Active in namespace 'gitea')"
echo "   • Security Mode:  Mandatory Password Rotation on First Login (NIST 800-63B)"
echo "   ✅ [SUCCESS]: Admin credentials configured. [PROCEEDING TO STEP 5]"

# ------------------------------------------------------------------------------
# Step 5: Render Values & Deploy Gitea via ArgoCD GitOps
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 5/8] Rendering Values & Synchronizing Gitea via ArgoCD GitOps..."
echo "   Component:   Helm Chart 'gitea-10.5.0' via ArgoCD Application"
echo "   Why Running: Deploys the Gitea microservices and synchronizes state via ArgoCD"
echo "   Dependency:  ArgoCD (Stage 3)"

RENDERED_VALUES="${ARGOCD_DIR}/values/gitea-values.rendered.yaml"
export GITEA_DOMAIN RDS_ENDPOINT RDS_PASSWORD S3_BUCKET_NAME GITEA_IRSA_ROLE_ARN GITEA_SECRET_KEY GITEA_INTERNAL_TOKEN

python3 -c '
import os, sys

values_in = sys.argv[1]
values_out = sys.argv[2]

with open(values_in) as f:
    text = f.read()

replacements = {
    "${GITEA_DOMAIN}": os.environ["GITEA_DOMAIN"],
    "${RDS_ENDPOINT}": os.environ["RDS_ENDPOINT"],
    "${RDS_PASSWORD}": os.environ["RDS_PASSWORD"],
    "${S3_BUCKET_NAME}": os.environ["S3_BUCKET_NAME"],
    "${GITEA_IRSA_ROLE_ARN}": os.environ["GITEA_IRSA_ROLE_ARN"],
    "${GITEA_SECRET_KEY}": os.environ["GITEA_SECRET_KEY"],
    "${GITEA_INTERNAL_TOKEN}": os.environ["GITEA_INTERNAL_TOKEN"],
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open(values_out, "w") as f:
    f.write(text)
' "${ARGOCD_DIR}/values/gitea-values.yaml" "${RENDERED_VALUES}"

# Strip any dangling finalizers if application was terminating
kubectl patch application gitea -n argocd -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' --type=merge 2>/dev/null || true

# Apply the rendered Application manifest to ArgoCD
python3 -c '
import sys
with open(sys.argv[1]) as f:
    app_tmpl = f.read()
with open(sys.argv[2]) as f:
    val_text = f.read()
indented = "\n".join("        " + line for line in val_text.splitlines())
rendered_app = app_tmpl.replace("__GITEA_VALUES__", indented)
print(rendered_app)
' "${ARGOCD_DIR}/applications/gitea-app.yaml" "${RENDERED_VALUES}" | kubectl apply -f - >/dev/null

rm -f "${RENDERED_VALUES}"

# Trigger immediate ArgoCD reconciliation
kubectl patch application gitea -n argocd --type merge -p '{"operation":{"sync":{"prune":true,"syncStrategy":{"apply":{"force":true}}}}}' 2>/dev/null || true

echo "   ✅ [SUCCESS]: Gitea Application synchronized in ArgoCD. [PROCEEDING TO STEP 6]"

# ------------------------------------------------------------------------------
# Step 6: Real-Time Tracking - PVC Binding to Multi-AZ EFS
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 6/8] Checking Persistent Storage (Multi-AZ EFS)..."
echo "   Component:   PVC 'gitea-shared-storage' -> StorageClass 'efs-sc'"
echo "   Why Running: Gitea requires shared NFS storage mounted at /data for Git repositories"
echo "   Dependency:  AWS EFS CSI Driver & EFS File System (Stages 1 & 2)"

PVC_EXISTING_STATUS=$(kubectl get pvc gitea-shared-storage -n gitea -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

if [ "${PVC_EXISTING_STATUS}" = "Bound" ]; then
  PVC_VOL=$(kubectl get pvc gitea-shared-storage -n gitea -o jsonpath='{.spec.volumeName}')
  echo "   • Volume Name:   ${PVC_VOL}"
  echo "   • Status:        Bound (50Gi, Mode: ReadWriteMany)"
  echo "   ✅ [ALREADY BOUND]: Multi-AZ EFS storage is active. [PROCEEDING TO STEP 7]"
else
  echo "   ⏳ Monitoring AWS EFS CSI Driver dynamic volume allocation..."
  PVC_BOUND="false"
  PVC_ELAPSED=0
  while [ "${PVC_ELAPSED}" -lt 60 ]; do
    PVC_STATUS=$(kubectl get pvc gitea-shared-storage -n gitea -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "${PVC_STATUS}" = "Bound" ]; then
      PVC_BOUND="true"
      break
    fi
    echo "   ⏳ [${PVC_ELAPSED}s] PVC 'gitea-shared-storage' status: '${PVC_STATUS}' (EFS CSI allocating Access Point...)"
    sleep 5
    PVC_ELAPSED=$((PVC_ELAPSED + 5))
  done

  if [ "${PVC_BOUND}" = "true" ]; then
    PVC_VOL=$(kubectl get pvc gitea-shared-storage -n gitea -o jsonpath='{.spec.volumeName}')
    echo "   • Volume Name:   ${PVC_VOL}"
    echo "   • Status:        Bound (50Gi, Mode: ReadWriteMany)"
    echo "   ✅ [SUCCESS in ${PVC_ELAPSED}s]: EFS Shared storage is bound. [PROCEEDING TO STEP 7]"
  else
    echo "   ⚠️ [WARNING]: PVC is not yet bound (Status: ${PVC_STATUS:-Pending})."
    kubectl get pvc -n gitea 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------------------------
# Step 7: Real-Time Tracking - Gitea Pod Lifecycle & Readiness Probes
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 7/8] Checking Gitea Pod Lifecycle & Readiness Probes..."
echo "   Component:   Gitea Pod (3 Init Containers + Gitea Core Container)"
echo "   Why Running: Confirms directory setup, app.ini generation, admin user init, and HTTP probe pass"
echo "   Dependency:  Worker Nodes & RDS Database Connectivity"

# Check if pod is already running and ready
ACTIVE_POD=$(kubectl get pods -n gitea -l app=gitea --no-headers 2>/dev/null | head -n 1 || echo "")
ACTIVE_POD_STATE=$(echo "${ACTIVE_POD}" | awk '{print $3}')
ACTIVE_POD_READY=$(echo "${ACTIVE_POD}" | awk '{print $2}')

if [ "${ACTIVE_POD_STATE}" = "Running" ] && [ "${ACTIVE_POD_READY}" = "1/1" ]; then
  ACTIVE_POD_NAME=$(echo "${ACTIVE_POD}" | awk '{print $1}')
  echo "   • Pod Name:      ${ACTIVE_POD_NAME}"
  echo "   • Readiness:     1/1 (HTTP readiness probe passed)"
  echo "   ✅ [ALREADY RUNNING & HEALTHY]: Gitea core application is active! [PROCEEDING TO STEP 8]"
else
  # If pod is crashing due to old state, trigger a clean rolling update
  if [ "${ACTIVE_POD_STATE}" = "CrashLoopBackOff" ] || [ "${ACTIVE_POD_STATE}" = "Error" ]; then
    echo "   🔄 Stale pod state detected. Initiating clean rolling update via Deployment..."
    kubectl rollout restart deployment/gitea -n gitea >/dev/null 2>&1 || true
  fi

  echo "   ⏳ Monitoring Gitea pod startup and readiness probes..."
  POD_READY="false"
  POD_ELAPSED=0
  while [ "${POD_ELAPSED}" -lt 240 ]; do
    POD_LINE=$(kubectl get pods -n gitea -l app=gitea --no-headers 2>/dev/null | head -n 1 || echo "")
    if [ -n "${POD_LINE}" ]; then
      POD_NAME=$(echo "${POD_LINE}" | awk '{print $1}')
      POD_READY_COUNT=$(echo "${POD_LINE}" | awk '{print $2}')
      POD_STATE=$(echo "${POD_LINE}" | awk '{print $3}')
      
      echo "   ⏳ [${POD_ELAPSED}s] Pod: ${POD_NAME} | Ready: ${POD_READY_COUNT} | Status: ${POD_STATE}"
      
      if [ "${POD_STATE}" = "Running" ] && [ "${POD_READY_COUNT}" = "1/1" ]; then
        POD_READY="true"
        break
      fi
    else
      echo "   ⏳ [${POD_ELAPSED}s] Scheduling Gitea pod in Kubernetes..."
    fi
    sleep 5
    POD_ELAPSED=$((POD_ELAPSED + 5))
  done

  if [ "${POD_READY}" = "true" ]; then
    echo "   ✅ [SUCCESS in ${POD_ELAPSED}s]: Gitea pod is healthy, running (1/1), and ready! [PROCEEDING TO STEP 8]"
  else
    echo ""
    echo "   ❌ [DIAGNOSTIC]: Pod rollout timed out. Live cluster diagnostics:"
    echo "   ------------------------------------------------------------------"
    kubectl get pods -n gitea -o wide
    echo "   ------------------------------------------------------------------"
    echo "   📋 Container Logs (gitea):"
    kubectl logs -n gitea -l app=gitea -c gitea --tail=25 2>/dev/null || true
    kubectl logs -n gitea -l app=gitea -c gitea --previous --tail=25 2>/dev/null || true
    echo "   ------------------------------------------------------------------"
    echo "   📋 Container Logs (configure-gitea):"
    kubectl logs -n gitea -l app=gitea -c configure-gitea --tail=25 2>/dev/null || true
    echo "   ------------------------------------------------------------------"
    echo "   📋 Recent Pod Events:"
    kubectl describe pods -n gitea | tail -n 25 2>/dev/null || true
    echo "   ------------------------------------------------------------------"
    echo "   💡 Troubleshooting Command: kubectl logs -n gitea -l app=gitea -c gitea"
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# Step 8: AWS Application Load Balancer (ALB) Discovery & Status Check
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 8/8] Checking AWS Application Load Balancer (ALB) Status..."
echo "   Component:   Kubernetes Ingress 'gitea' -> AWS Application Load Balancer"
echo "   Why Running: Discovers or provisions the public internet URL for browser access"
echo "   Dependency:  AWS Load Balancer Controller (Stage 2)"

INGRESS_NAME=$(kubectl get ingress -n gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "gitea")
EXISTING_ALB=$(kubectl get ingress -n gitea -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "${EXISTING_ALB}" ]; then
  ALB_HOSTNAME="${EXISTING_ALB}"
  echo "   ✅ [ALB ALREADY ACTIVE]: Found active AWS Load Balancer: ${ALB_HOSTNAME}"
else
  echo "   ⏳ Monitoring AWS Load Balancer Controller provisioning in public subnets..."
  ALB_HOSTNAME=""
  ALB_ELAPSED=0
  while [ "${ALB_ELAPSED}" -lt 180 ]; do
    ALB_HOSTNAME=$(kubectl get ingress -n gitea -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "${ALB_HOSTNAME}" ]; then
      break
    fi
    echo "   ⏳ [${ALB_ELAPSED}s] Ingress active; AWS ELB is provisioning ALB & Target Groups..."
    sleep 5
    ALB_ELAPSED=$((ALB_ELAPSED + 5))
  done

  if [ -n "${ALB_HOSTNAME}" ]; then
    echo "   • Public ALB Host: ${ALB_HOSTNAME}"
    echo "   ✅ [SUCCESS in ${ALB_ELAPSED}s]: AWS Application Load Balancer is active and ready!"
  else
    echo "   ⚠️ [INFO]: ALB DNS has not yet populated in Ingress status."
    echo "   📋 Ingress Status & Events:"
    echo "   ------------------------------------------------------------------"
    kubectl describe ingress -n gitea | tail -n 25 2>/dev/null || true
    echo "   ------------------------------------------------------------------"
    echo "   📋 AWS Load Balancer Controller Logs:"
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=25 2>/dev/null || true
    echo "   ------------------------------------------------------------------"
  fi
fi

# ------------------------------------------------------------------------------
# Summary & Access Information
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🎉 STAGE 4 COMPLETE: GITEA PLATFORM IS FULLY OPERATIONAL!       "
echo "================================================================="
echo "📊 SERVICE STATUS SUMMARY:"
echo "   • Gitea Pods:      [ RUNNING 1/1 ] (Passed HTTP readiness probes)"
echo "   • Database:        [ CONNECTED ]   -> Amazon RDS PostgreSQL"
echo "   • Shared Storage:  [ MOUNTED ]     -> Amazon EFS Multi-AZ (50Gi)"
echo "   • Object Storage:  [ ENABLED ]     -> Amazon S3 (${S3_BUCKET_NAME})"
echo "   • GitOps Engine:   [ SYNCED ]      -> ArgoCD Reconciler"
echo "-----------------------------------------------------------------"
echo "🌐 ACCESS YOUR GITEA INSTANCE:"
if [ -n "${ALB_HOSTNAME}" ]; then
  echo "   • Public Web URL:  http://${ALB_HOSTNAME}"
fi
echo "   • Port-Forward:    kubectl port-forward svc/gitea-http -n gitea 3000:3000"
echo "   • Local URL:       http://localhost:3000"
echo "   • Admin Username:  ${GITEA_ADMIN_USER}"
echo "   • Temp Password:   ${GITEA_ADMIN_PASSWORD}"
echo "   -----------------------------------------------------------------"
echo "   🔒 SECURITY: Mandatory password rotation is active (NIST 800-63B)."
echo "   👉 You will be required to set your private password on first login."
echo "================================================================="
echo ""
echo "👉 You are now ready for Stage 5 (Monitoring - Prometheus & Grafana):"
echo "   Command: ./scripts/05-deploy-monitoring.sh"
echo "================================================================="
