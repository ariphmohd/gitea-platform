#!/usr/bin/env bash
# ==============================================================================
# Stage 2: Bootstrap EKS Cluster & Core Controllers
# ==============================================================================
# Prepares the Kubernetes platform with core controllers and storage:
#   1. Configures kubectl context with AWS EKS
#   2. Creates required namespaces (argocd, gitea, monitoring, datadog)
#   3. Enables AWS VPC CNI Prefix Delegation (increases pod density to 110 pods/node)
#   4. Applies Multi-AZ EFS StorageClass (for dynamic PVC provisioning in Stage 04)
#   5. Deploys AWS Load Balancer Controller (provisions public ALBs for Gitea)
#   6. Deploys AWS EFS CSI Driver (mounts EFS NFS storage for Git repos in Stage 04)
#
# Each step includes automated health checks and verification.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PLATFORM_DIR}/terraform"
K8S_DIR="${PLATFORM_DIR}/k8s"
ARGOCD_DIR="${PLATFORM_DIR}/argocd"

AWS_REGION="${AWS_REGION:-ap-south-1}"
if [ -f "${ARGOCD_DIR}/env.conf" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf"
elif [ -f "${ARGOCD_DIR}/env.conf.example" ]; then
  # shellcheck source=/dev/null
  source "${ARGOCD_DIR}/env.conf.example"
fi

echo "================================================================="
echo "🔌 STAGE 2: Bootstrapping EKS Cluster & Core Controllers        "
echo "================================================================="

cd "${TERRAFORM_DIR}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
VPC_ID=$(terraform output -raw vpc_id)
EFS_ID=$(terraform output -raw efs_file_system_id)
ALB_CONTROLLER_IRSA_ROLE_ARN=$(terraform output -raw alb_controller_irsa_role_arn)
EFS_CSI_IRSA_ROLE_ARN=$(terraform output -raw efs_csi_irsa_role_arn)

# ------------------------------------------------------------------------------
# Step 1: Configure kubectl context
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 1/6] Configuring kubectl Authentication..."
echo "   Component:   AWS IAM Authenticator -> ~/.kube/config"
echo "   Usage:       Enables kubectl & helm CLI to communicate with EKS (All Stages)"
aws eks --region "${AWS_REGION}" update-kubeconfig --name "${CLUSTER_NAME}" >/dev/null

echo "   🔍 Verifying EKS API connectivity and worker nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${NODE_COUNT}" -gt 0 ]; then
  echo "   ✅ Verified: Connected to cluster '${CLUSTER_NAME}'. Found ${NODE_COUNT} active worker nodes."
else
  echo "   ❌ Error: Unable to reach EKS cluster nodes. Check AWS credentials."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Ensure Required Namespaces Exist
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 2/6] Ensuring Application Namespaces Exist..."
echo "   Component:   Kubernetes Namespaces (argocd, gitea, monitoring, datadog)"
echo "   Usage:       Isolates workloads across Stages 03, 04, 05, and 06"
for ns in argocd gitea monitoring datadog kube-system; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

echo "   🔍 Verifying namespaces..."
for ns in argocd gitea monitoring datadog kube-system; do
  kubectl get namespace "${ns}" >/dev/null
  echo "   ✅ Namespace '${ns}' is active."
done

# ------------------------------------------------------------------------------
# Step 3: Enable AWS VPC CNI Prefix Delegation
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 3/6] Configuring AWS VPC CNI Prefix Delegation..."
echo "   Component:   aws-node DaemonSet (IPAM Controller)"
echo "   Usage:       Increases pod IP capacity from 11 up to 110 pods per worker node"
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true >/dev/null
kubectl set env daemonset aws-node -n kube-system WARM_PREFIX_TARGET=1 >/dev/null

echo "   🔍 Verifying aws-node DaemonSet rollout..."
kubectl rollout status daemonset/aws-node -n kube-system --timeout=60s >/dev/null
echo "   ✅ Verified: AWS VPC CNI Prefix Delegation is active across all worker nodes."

# ------------------------------------------------------------------------------
# Step 4: Apply Multi-AZ EFS StorageClass
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 4/6] Configuring Multi-AZ EFS StorageClass..."
echo "   Component:   StorageClass 'efs-sc' (NFS Provisioner)"
echo "   Usage:       Enables Gitea (Stage 04) to dynamically create and mount shared Git storage"
echo "   EFS ID:      ${EFS_ID}"
kubectl delete storageclass efs-sc --ignore-not-found=true >/dev/null
sed "s/__EFS_FILE_SYSTEM_ID__/${EFS_ID}/g" "${K8S_DIR}/efs-storageclass.yaml" | kubectl apply -f - >/dev/null

echo "   🔍 Verifying StorageClass 'efs-sc'..."
SC_VERIFY=$(kubectl get storageclass efs-sc -o jsonpath='{.parameters.fileSystemId}' 2>/dev/null || echo "")
if [ "${SC_VERIFY}" = "${EFS_ID}" ]; then
  echo "   ✅ Verified: StorageClass 'efs-sc' is active and bound to EFS '${EFS_ID}'."
else
  echo "   ❌ Error: StorageClass 'efs-sc' parameter mismatch."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 5: Deploy AWS Load Balancer Controller
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 5/6] Deploying AWS Load Balancer Controller..."
echo "   Component:   aws-load-balancer-controller (Helm Release in kube-system)"
echo "   Usage:       Watches Kubernetes Ingresses & creates physical AWS ALBs (Stage 04)"
echo "   IAM Role:    ${ALB_CONTROLLER_IRSA_ROLE_ARN}"

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${ALB_CONTROLLER_IRSA_ROLE_ARN}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set enableServiceMutatorWebhook=false >/dev/null

echo "   🔍 Waiting for AWS Load Balancer Controller pod to become ready..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s >/dev/null
echo "   ✅ Verified: AWS Load Balancer Controller is healthy and running."

# ------------------------------------------------------------------------------
# Step 6: Deploy AWS EFS CSI Driver
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 6/6] Deploying AWS EFS CSI Driver..."
echo "   Component:   aws-efs-csi-driver (Controller Deployment & Node Daemonsets in kube-system)"
echo "   Usage:       Mounts Multi-AZ EFS storage into Gitea pods over NFS on Port 2049 (Stage 04)"
echo "   IAM Role:    ${EFS_CSI_IRSA_ROLE_ARN}"

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/ >/dev/null 2>&1 || true
helm repo update aws-efs-csi-driver >/dev/null

helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.name=efs-csi-controller-sa \
  --set controller.serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="${EFS_CSI_IRSA_ROLE_ARN}" >/dev/null

echo "   🔍 Waiting for AWS EFS CSI Driver controller pod to become ready..."
kubectl rollout status deployment/efs-csi-controller -n kube-system --timeout=120s >/dev/null
echo "   ✅ Verified: AWS EFS CSI Driver is healthy and running."

# ------------------------------------------------------------------------------
# Summary & Next Stage Confirmation
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🎉 STAGE 2 VERIFICATION SUMMARY: ALL CORE COMPONENTS READY!     "
echo "================================================================="
echo "1. 🔌 Kubeconfig Auth:      [ READY ] (Cluster: ${CLUSTER_NAME}, Nodes: ${NODE_COUNT})"
echo "2. 📁 App Namespaces:       [ READY ] (argocd, gitea, monitoring, datadog)"
echo "3. 🚀 Prefix Delegation:    [ READY ] (aws-node DaemonSet healthy)"
echo "4. 💾 Multi-AZ StorageClass:[ READY ] (efs-sc -> ${EFS_ID})"
echo "5. 🌐 ALB Controller:       [ READY ] (Ready to provision public ALBs in Stage 04)"
echo "6. 📦 EFS CSI Driver:       [ READY ] (Ready to mount Git repositories in Stage 04)"
echo "================================================================="
echo ""
echo "👉 You are now 100% verified and ready for Stage 3:"
echo "   Command: ./scripts/03-deploy-argocd.sh"
echo "================================================================="
