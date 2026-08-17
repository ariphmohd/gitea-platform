#!/usr/bin/env bash
# ==============================================================================
# Gitea Platform - Standalone Post-Teardown EFS Cleanup Utility
# ==============================================================================
# Run this script ONLY after everything has been destroyed and no other
# infrastructure or Kubernetes clusters are running, to remove any leftover
# orphaned EFS file systems, mount targets, or access points in AWS.
# ==============================================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"

echo "================================================================="
echo "🧹 Post-Teardown Orphaned EFS Cleanup Utility (${AWS_REGION})"
echo "================================================================="

# 1. Check AWS Authentication
command -v aws >/dev/null 2>&1 || { echo "❌ Error: aws-cli is required."; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "❌ Error: AWS authentication failed. Configure credentials."; exit 1; }

# 2. Identify Target EFS File System(s)
TARGET_EFS_ID="${1:-}"

if [ -z "${TARGET_EFS_ID}" ]; then
  echo "🔍 Scanning AWS region ${AWS_REGION} for Gitea EFS file systems..."
  TARGET_EFS_ID=$(aws efs describe-file-systems --region "${AWS_REGION}" \
    --query "FileSystems[?contains(Name, 'gitea') || contains(CreationToken, 'gitea')].FileSystemId" \
    --output text 2>/dev/null || true)
fi

if [ -z "${TARGET_EFS_ID}" ]; then
  echo "ℹ️ No leftover Gitea EFS file systems found in ${AWS_REGION}."
  echo "If you have a specific EFS ID to delete, run:"
  echo "   ./scripts/cleanup-efs.sh <fs-xxxxxxxxxxxxxxxxx>"
  exit 0
fi

echo "🎯 Found Leftover EFS File System(s): ${TARGET_EFS_ID}"
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "   • File System: ${TARGET_EFS_ID}"
echo "   • All remaining Access Points"
echo "   • All Mount Targets & ENIs"
echo ""

read -p "Are you sure you want to permanently delete this EFS? (type 'yes' to confirm): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
  echo "❌ Operation cancelled."
  exit 0
fi

# 3. Clean up each EFS File System
for fs_id in ${TARGET_EFS_ID}; do
  echo ""
  echo "🗑️  Purging EFS: ${fs_id}..."

  # Step A: Delete all Access Points
  ACCESS_POINTS=$(aws efs describe-access-points --file-system-id "${fs_id}" --region "${AWS_REGION}" --query "AccessPoints[].AccessPointId" --output text 2>/dev/null || true)
  if [ -n "${ACCESS_POINTS}" ]; then
    for ap in ${ACCESS_POINTS}; do
      echo "  -> Deleting Access Point: ${ap}"
      aws efs delete-access-point --access-point-id "${ap}" --region "${AWS_REGION}" || true
    done
  fi

  # Step B: Delete all Mount Targets
  MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "${fs_id}" --region "${AWS_REGION}" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || true)
  if [ -n "${MOUNT_TARGETS}" ]; then
    for mt in ${MOUNT_TARGETS}; do
      echo "  -> Deleting Mount Target: ${mt}"
      aws efs delete-mount-target --mount-target-id "${mt}" --region "${AWS_REGION}" || true
    done

    echo "  ⏳ Waiting for Mount Targets to release..."
    while true; do
      REMAINING=$(aws efs describe-mount-targets --file-system-id "${fs_id}" --region "${AWS_REGION}" --query "MountTargets[].MountTargetId" --output text 2>/dev/null || true)
      if [ -z "${REMAINING}" ]; then
        echo "  ✅ All Mount Targets deleted."
        break
      fi
      sleep 5
    done
  fi

  # Step C: Delete the File System
  echo "  -> Deleting EFS File System: ${fs_id}"
  aws efs delete-file-system --file-system-id "${fs_id}" --region "${AWS_REGION}"
  echo "  ✅ EFS ${fs_id} deleted."
done

echo ""
echo "================================================================="
echo "✅ Cleanup complete. All leftover EFS resources have been removed."
echo "================================================================="
