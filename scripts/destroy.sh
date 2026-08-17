#!/usr/bin/env bash
# ==============================================================================
# Gitea Platform - Teardown Script with Automated Ingress, ENI & VPC Pre-Cleanup
# ==============================================================================
# 1. Confirms destruction intent
# 2. Displays estimated AWS resource teardown durations for user awareness
# 3. Gracefully removes Kubernetes Ingresses to trigger AWS ALB deletion
# 4. Strips PVC finalizers and uninstalls Helm controllers
# 5. Actively sweeps and purges dangling ALBs, Target Groups, and ENIs in the VPC
# 6. Executes non-blocking terraform destroy with automated dependency retry
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

echo "================================================================="
echo "⚠️  WARNING: PERMANENT INFRASTRUCTURE & DATA DELETION             "
echo "================================================================="
echo "This action will permanently delete all cloud resources:"
echo "  • Amazon EKS Cluster & Graviton2 Worker Nodes"
echo "  • Amazon RDS PostgreSQL Database (all DB tables & data)"
echo "  • Amazon EFS File System (all Git repository files)"
echo "  • Amazon S3 Buckets (Git LFS, packages, and avatars)"
echo "  • AWS Application Load Balancers (ALBs) & Ingresses"
echo "  • VPC, Subnets, NAT Gateways, and IAM/IRSA Roles"
echo "================================================================="
echo ""
echo "ℹ️  ESTIMATED AWS RESOURCE TEARDOWN TIMELINES:"
echo "  • RDS PostgreSQL Instance: ~2-3 mins (AWS storage detach & safety lock)"
echo "  • EKS Cluster & Node Group: ~3-4 mins (AWS ENI detach & instance drain)"
echo "  • NAT Gateway & VPC:        ~1-2 mins (AWS EIP release & subnet unlock)"
echo "  • Total Expected Duration:  ~5-7 mins (Standard AWS Cloud timeline)"
echo "================================================================="
echo ""

read -p "Are you sure you want to delete everything? (type 'yes' to confirm): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
  echo "❌ Teardown cancelled by user. No resources were deleted."
  exit 0
fi

cd "${TERRAFORM_DIR}"
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

# ------------------------------------------------------------------------------
# Phase 1: Graceful In-Cluster Cleanup
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🧹 PHASE 1: Graceful Kubernetes Ingress & Storage Cleanup        "
echo "================================================================="

if kubectl version --client >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
  echo "1. Deleting all Kubernetes Ingresses (triggers AWS ALB release)..."
  kubectl delete ingress --all -A --timeout=60s --ignore-not-found=true || true

  echo "2. Stripping finalizers and removing ArgoCD applications..."
  for app in $(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
    kubectl patch application "${app}" -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    kubectl delete application "${app}" -n argocd --force --grace-period=0 2>/dev/null || true
  done

  echo "3. Stripping PVC finalizers..."
  kubectl patch pvc --all -A -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  kubectl delete pvc --all -A --timeout=60s --ignore-not-found=true || true

  echo "4. Removing Helm controllers..."
  helm uninstall gitea -n gitea 2>/dev/null || true
  helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
  helm uninstall argocd -n argocd 2>/dev/null || true
  helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
  helm uninstall aws-efs-csi-driver -n kube-system 2>/dev/null || true

  echo "⏳ Waiting 25 seconds for AWS ELB to release Public Subnet ENIs..."
  sleep 25
else
  echo "ℹ️ Kubernetes cluster not reachable. Proceeding directly to AWS CLI sweep."
fi

# ------------------------------------------------------------------------------
# Phase 2: Active AWS Resource Sweep (ALBs, Target Groups, Dangling ENIs)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🔍 PHASE 2: Sweeping VPC for Dangling Load Balancers & ENIs      "
echo "================================================================="

sweep_vpc_dependencies() {
  local vpc="$1"
  if [ -z "${vpc}" ]; then
    return 0
  fi

  echo "   🔎 Checking for any remaining ALBs in VPC (${vpc})..."
  local alb_arns
  alb_arns=$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" --query "LoadBalancers[?VpcId=='${vpc}'].LoadBalancerArn" --output text 2>/dev/null || true)
  for alb_arn in ${alb_arns}; do
    if [ -n "${alb_arn}" ] && [ "${alb_arn}" != "None" ]; then
      echo "      🗑️ Deleting ALB: ${alb_arn}"
      aws elbv2 delete-load-balancer --load-balancer-arn "${alb_arn}" --region "${AWS_REGION}" 2>/dev/null || true
    fi
  done

  echo "   🔎 Checking for any remaining Target Groups in VPC (${vpc})..."
  local tg_arns
  tg_arns=$(aws elbv2 describe-target-groups --region "${AWS_REGION}" --query "TargetGroups[?VpcId=='${vpc}'].TargetGroupArn" --output text 2>/dev/null || true)
  for tg_arn in ${tg_arns}; do
    if [ -n "${tg_arn}" ] && [ "${tg_arn}" != "None" ]; then
      echo "      🗑️ Deleting Target Group: ${tg_arn}"
      aws elbv2 delete-target-group --target-group-arn "${tg_arn}" --region "${AWS_REGION}" 2>/dev/null || true
    fi
  done

  echo "   🔎 Checking for unattached/available ENIs in VPC (${vpc})..."
  local eni_ids
  eni_ids=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc}" "Name=status,Values=available" --region "${AWS_REGION}" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null || true)
  for eni_id in ${eni_ids}; do
    if [ -n "${eni_id}" ] && [ "${eni_id}" != "None" ]; then
      echo "      🗑️ Deleting unattached ENI: ${eni_id}"
      aws ec2 delete-network-interface --network-interface-id "${eni_id}" --region "${AWS_REGION}" 2>/dev/null || true
    fi
  done
}

if [ -n "${VPC_ID}" ]; then
  sweep_vpc_dependencies "${VPC_ID}"
fi

# ------------------------------------------------------------------------------
# Phase 3: Terraform Infrastructure Teardown
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "💥 PHASE 3: Executing Terraform Infrastructure Destroy           "
echo "================================================================="
echo "⏳ Destroying cloud resources (RDS, EKS, EFS, S3, IAM, VPC)..."
echo "   (Note: RDS and EKS teardown typically take ~3-4 minutes on AWS)"
echo "-----------------------------------------------------------------"

if ! terraform destroy -auto-approve; then
  echo ""
  echo "⚠️ Terraform encountered a dependency hold on VPC. Running deep ENI sweep..."
  if [ -n "${VPC_ID}" ]; then
    echo "⏳ Waiting 20 seconds for AWS instance terminations to settle..."
    sleep 20
    sweep_vpc_dependencies "${VPC_ID}"
  fi
  echo "🔄 Retrying final terraform destroy..."
  terraform destroy -auto-approve
fi

echo ""
echo "================================================================="
echo "🎉 TEARDOWN COMPLETE: All infrastructure cleanly destroyed!      "
echo "================================================================="
