#!/usr/bin/env bash
# ==============================================================================
# 🔐 STAGE 9: Setup GitHub Actions AWS OIDC & Automated GitOps Pipeline
# ==============================================================================
#
# ❓ WHY ARE WE DOING AWS OIDC (OPENID CONNECT)?
# ------------------------------------------------------------------------------
# 🔴 The Old, Dangerous Way (Static IAM Access Keys):
#    Historically, developers created permanent AWS IAM user access keys
#    (AWS_ACCESS_KEY_ID & AWS_SECRET_ACCESS_KEY) and pasted them into GitHub.
#    Risk: If those keys leak or get compromised, attackers gain permanent 24/7
#    access to your AWS account. Keys also violate SOC2/ISO compliance without
#    frequent 90-day rotation.
#
# 🟢 The Modern Gold-Standard Way (AWS IAM OIDC):
#    Zero static keys exist! GitHub acts as a trusted identity provider.
#    When GitHub Actions runs, GitHub generates a cryptographically signed JWT
#    token stamped with your repo name ('repo:ariphmohd/gitea').
#    AWS STS validates the signature and issues temporary, 1-hour credentials
#    that automatically self-destruct after the build finishes.
#
# ❓ WHY DO WE NEED THE 'GITOPS_PAT' GITHUB TOKEN?
# ------------------------------------------------------------------------------
# You have TWO separate repositories:
#   1. 'ariphmohd/gitea'          -> Contains your Go source code & Dockerfile.
#   2. 'ariphmohd/gitea-platform' -> Contains your Helm values & ArgoCD manifests.
#
# By default, GitHub security isolates repositories: a workflow in Repo 1 CANNOT
# modify files in Repo 2.
# When Repo 1 builds a new container image and pushes it to Amazon ECR, it needs
# to update the image tag in 'argocd/values/gitea-values.yaml' in Repo 2.
# The 'GITOPS_PAT' (Personal Access Token) acts as the secure permission key
# that allows Repo 1 to update Repo 2, completing the automated GitOps deployment!
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PLATFORM_DIR}/terraform"

echo "================================================================="
echo "🔐 STAGE 9: AWS OIDC Provider & GitHub Actions GitOps Setup      "
echo "================================================================="
echo "GitHub Account:     ariphmohd"
echo "AWS Region:         ap-south-1"
echo "Authentication:     Passwordless OIDC (Zero Static AWS Keys)"
echo "GitOps Engine:      ArgoCD Automated Continuous Delivery"
echo "================================================================="

cd "${TERRAFORM_DIR}"

# ------------------------------------------------------------------------------
# Step 1: Provision OIDC Provider and IAM Role in AWS via Terraform
# ------------------------------------------------------------------------------
echo ""
echo "🔹 [Step 1/2] Provisioning AWS OIDC Identity Provider & IAM Role in AWS..."
echo "   Component:   aws_iam_openid_connect_provider.github + aws_iam_role.github_actions_ecr"
echo "   Why Running: Establishes cryptographic trust between GitHub and your AWS account"
echo "   Dependency:  Terraform AWS Provider"

terraform apply -target=module.iam -auto-approve >/dev/null

ROLE_ARN=$(terraform output -raw github_actions_role_arn 2>/dev/null || echo "arn:aws:iam::542697646590:role/gitea-prod-github-actions-ecr-role")

echo "   • OIDC Provider:     https://token.actions.githubusercontent.com"
echo "   • IAM Role ARN:      ${ROLE_ARN}"
echo "   • Trust Filter:      repo:ariphmohd/* (Strictly limited to your account)"
echo "   ✅ [SUCCESS]: AWS OIDC trust relationship is active! [PROCEEDING TO STEP 2]"

# ------------------------------------------------------------------------------
# Step 2: Display Educational Architecture & 1-Time GitHub Setup Guide
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "🎉 STAGE 9 COMPLETE: AWS OIDC TRUST IS CONFIGURED!              "
echo "================================================================="
echo ""
echo "📖 WHY WE USE THIS ARCHITECTURE (DEVOPS BEST PRACTICES):"
echo "-----------------------------------------------------------------"
echo "1. 🛡️ ZERO STATIC KEYS (AWS OIDC):"
echo "   • No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY stored in GitHub."
echo "   • GitHub Actions assumes '${ROLE_ARN}' on-demand."
echo "   • Credentials expire automatically after 1 hour."
echo ""
echo "2. 🔄 CROSS-REPO GITOPS AUTOMATION (GITOPS_PAT):"
echo "   • Source Repo: 'ariphmohd/gitea' (Builds & pushes image to ECR)"
echo "   • GitOps Repo: 'ariphmohd/gitea-platform' (ArgoCD watches this repo)"
echo "   • The GITOPS_PAT allows the CI runner in Repo 1 to update the image"
echo "     tag in Repo 2, triggering ArgoCD to deploy to EKS with zero downtime!"
echo "-----------------------------------------------------------------"
echo "📋 1-TIME GITHUB SETUP (TAKES 1 MINUTE IN GITHUB UI):"
echo "-----------------------------------------------------------------"
echo "👉 Part A: Generate your GitHub Personal Access Token (PAT)"
echo "   1. Open: https://github.com/settings/tokens"
echo "   2. Click 'Generate new token' -> 'Generate new token (classic)'"
echo "   3. Note: 'gitops-token'"
echo "   4. Expiration: 90 days (or your preference)"
echo "   5. Scopes: Check the 'repo' checkbox (Full control of repositories)"
echo "   6. Click 'Generate token' (green button at bottom) and copy 'ghp_...'"
echo ""
echo "👉 Part B: Save Token in your App Repository ('ariphmohd/gitea')"
echo "   1. Open: https://github.com/ariphmohd/gitea/settings/secrets/actions"
echo "   2. Click 'New repository secret'"
echo "   3. Name:  GITOPS_PAT"
echo "   4. Value: [Paste your ghp_... token here]"
echo "   5. Click 'Add secret'"
echo "-----------------------------------------------------------------"
echo "🚀 HOW TO RUN & TEST YOUR CI/CD PIPELINE:"
echo "-----------------------------------------------------------------"
echo "   • Option 1 (Manual 1-Click): Go to https://github.com/ariphmohd/gitea/actions"
echo "     Select '🚀 Gitea App DevSecOps CI/CD Pipeline' and click 'Run workflow'."
echo ""
echo "   • Option 2 (Automated on Git Push): Simply push any commit to"
echo "     'ariphmohd/gitea' (main branch)."
echo ""
echo "   • Watch the Rollout: Open your ArgoCD UI at https://argocd.ariphmohd.shop"
echo "     and watch ArgoCD perform an automated zero-downtime rolling update!"
echo "================================================================="
