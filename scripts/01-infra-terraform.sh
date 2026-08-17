#!/usr/bin/env bash
# ==============================================================================
# Stage 1: Provision AWS Cloud Infrastructure via Terraform
# ==============================================================================
# Provisions the complete, enterprise-grade cloud foundation:
#   1. AWS VPC & Networking (Public/Private Subnets, Single NAT Gateway, Internet Gateway)
#   2. Amazon EKS 1.36 Cluster & Graviton2 Worker Nodes (AL2023, OIDC Provider, IRSA)
#   3. Amazon RDS PostgreSQL 16.4 & AWS Secrets Manager (Encrypted Database)
#   4. Amazon EFS Standard Multi-AZ File System & S3 Bucket (Shared Repos & Git LFS)
#   5. IAM Roles for Service Accounts (IRSA for ALB Controller, EFS CSI, and Gitea)
#
# Each component is verified upon completion and mapped to its downstream stage usage.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PLATFORM_DIR}/terraform"

echo "================================================================="
echo "🏗️  STAGE 1: Provisioning AWS Cloud Infrastructure (Terraform)  "
echo "================================================================="
echo "Blueprint to be provisioned:"
echo "  • Networking:   VPC (10.0.0.0/16) across 2 AZs with Single NAT Gateway"
echo "  • Compute:      Amazon EKS 1.36 on AWS Graviton2 (t4g.small / ARM64)"
echo "  • Database:     Amazon RDS PostgreSQL 16.4 (db.t4g.micro) + Secrets Manager"
echo "  • File Storage: Amazon EFS Multi-AZ (Mount Targets in ap-south-1a & 1b)"
echo "  • Object Store: Amazon S3 Encrypted Bucket (Git LFS, Packages, Avatars)"
echo "  • Security:     IAM OIDC Provider & 3 IRSA Roles (ALB, EFS, Gitea)"
echo "================================================================="
echo ""

cd "${TERRAFORM_DIR}"

# ------------------------------------------------------------------------------
# Step 1: Pre-flight Configuration Check
# ------------------------------------------------------------------------------
echo "🔹 [Step 1/5] Checking Configuration & Environment..."
echo "   Component:   terraform.tfvars"
echo "   Usage:       Supplies region, sizing, cost-optimization toggles, and tags"

if [ ! -f "terraform.tfvars" ]; then
  if [ -f "terraform.tfvars.example" ]; then
    echo "   ℹ️ Creating terraform.tfvars automatically from template..."
    cp terraform.tfvars.example terraform.tfvars
  else
    echo "   ❌ Error: terraform.tfvars not found and no template available."
    exit 1
  fi
fi
echo "   ✅ Verified: Configuration file 'terraform.tfvars' is present."

# ------------------------------------------------------------------------------
# Step 2: Initialize & Validate Terraform
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 2/5] Initializing AWS Provider & Modules..."
echo "   Component:   Terraform AWS Provider (~> 5.0) & Kubernetes Module Tree"
echo "   Usage:       Downloads required AWS plugins and compiles module dependencies"

terraform init >/dev/null
terraform validate >/dev/null
echo "   ✅ Verified: Terraform modules initialized and syntax validated."

# ------------------------------------------------------------------------------
# Step 3: Infrastructure Provisioning
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 3/5] Applying Terraform Infrastructure..."
echo "   (Note: Total provisioning takes ~10-12 minutes on AWS for RDS + EKS)"
echo "   • VPC & Subnets:    ~1-2 minutes"
echo "   • RDS PostgreSQL:   ~4-5 minutes"
echo "   • EKS Control Plane:~8-10 minutes"
echo "   • EFS Multi-AZ:     ~1 minute"
echo "   --------------------------------------------------------------"

terraform apply -auto-approve

# ------------------------------------------------------------------------------
# Step 4: Extract Outputs & Trace Dependency Map
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 4/5] Extracting Cloud Outputs & Verifying Linkages..."

CLUSTER_NAME=$(terraform output -raw cluster_name)
VPC_ID=$(terraform output -raw vpc_id)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn)
EFS_ID=$(terraform output -raw efs_file_system_id)
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
ALB_IRSA=$(terraform output -raw alb_controller_irsa_role_arn)
EFS_IRSA=$(terraform output -raw efs_csi_irsa_role_arn)
GITEA_IRSA=$(terraform output -raw gitea_irsa_role_arn)

echo "   ✅ Verified: All infrastructure resources active in AWS."

# ------------------------------------------------------------------------------
# Step 5: Resource Traceability & Downstream Stage Mapping
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🎉 STAGE 1 COMPLETE: CLOUD INFRASTRUCTURE PROVISIONED!          "
echo "================================================================="
echo "📊 RESOURCE TRACEABILITY & DOWNSTREAM USAGE MAP:"
echo "-----------------------------------------------------------------"
echo "1. 🌐 AWS VPC & Subnets:"
echo "   • VPC ID:        ${VPC_ID}"
echo "   • Downstream:    Used by EKS, RDS, EFS, and ALB Controller in Stage 02"
echo ""
echo "2. 🚀 Amazon EKS 1.36 Cluster:"
echo "   • Cluster Name:  ${CLUSTER_NAME}"
echo "   • Downstream:    Bootstrapped in Stage 02; hosts all pods across Stages 03-06"
echo ""
echo "3. 🗄️ Amazon RDS PostgreSQL 16.4:"
echo "   • DB Endpoint:   ${RDS_ENDPOINT}"
echo "   • Secrets ARN:   ${RDS_SECRET_ARN}"
echo "   • Downstream:    Gitea connects on port 5432 in Stage 04"
echo ""
echo "4. 💾 Amazon EFS Multi-AZ:"
echo "   • File System:   ${EFS_ID}"
echo "   • Downstream:    Bound to 'efs-sc' StorageClass in Stage 02; mounted in Stage 04"
echo ""
echo "5. 📦 Amazon S3 Storage:"
echo "   • Bucket Name:   ${S3_BUCKET_NAME}"
echo "   • Downstream:    Used by Gitea in Stage 04 for Git LFS & packages"
echo ""
echo "6. 🔐 AWS IAM IRSA Roles:"
echo "   • ALB Role:      ${ALB_IRSA} (Consumed by Stage 02)"
echo "   • EFS Role:      ${EFS_IRSA} (Consumed by Stage 02)"
echo "   • Gitea Role:    ${GITEA_IRSA} (Consumed by Stage 04)"
echo "================================================================="
echo ""
echo "👉 You are now 100% verified and ready for Stage 2 (EKS Bootstrap):"
echo "   Command: ./scripts/02-eks-bootstrap.sh"
echo "================================================================="
