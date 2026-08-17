#!/usr/bin/env python3
"""
=============================================================================
Gitea Platform - Global Multi-Region AWS Storage Cleanup Utility (Python)
=============================================================================
This script scans ALL AWS regions (or specific regions) for:
1. Unattached / Orphaned EBS Volumes (Status: 'available')
2. Unused / Orphaned EFS File Systems (0 Mount Targets or tagged 'gitea')

Works out-of-the-box using Python 3 and the AWS CLI.
=============================================================================
"""

import argparse
import json
import os
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional


def run_aws_command(args: List[str], region: Optional[str] = None) -> Optional[Any]:
    """Runs an AWS CLI command and returns parsed JSON output."""
    cmd = ["aws"] + args
    if region:
        cmd += ["--region", region]
    cmd += ["--output", "json"]

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        if result.stdout.strip():
            return json.loads(result.stdout)
        return None
    except subprocess.CalledProcessError as e:
        # Ignore errors for regions where a service might not be enabled
        return None
    except FileNotFoundError:
        sys.stderr.write("❌ Error: 'aws' CLI executable not found in PATH.\n")
        sys.exit(1)


def get_all_aws_regions() -> List[str]:
    """Fetches all enabled AWS regions for the current account."""
    data = run_aws_command(["ec2", "describe-regions", "--query", "Regions[].RegionName"])
    if isinstance(data, list) and len(data) > 0:
        return sorted(data)
    
    # Fallback to standard major AWS regions if query fails
    return [
        "ap-south-1", "ap-south-2", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1",
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-central-1", "eu-north-1", "me-central-1", "sa-east-1"
    ]


def get_unattached_ebs_volumes(region: str) -> List[Dict[str, Any]]:
    """Fetches all EBS volumes with status 'available' (unattached) in a region."""
    data = run_aws_command(
        ["ec2", "describe-volumes", "--filters", "Name=status,Values=available"],
        region
    )
    if not data or "Volumes" not in data:
        return []
    
    volumes = []
    for v in data["Volumes"]:
        name_tag = "-"
        for tag in v.get("Tags", []):
            if tag.get("Key") == "Name":
                name_tag = tag.get("Value", "-")
                break
        volumes.append({
            "region": region,
            "id": v.get("VolumeId"),
            "size": v.get("Size"),
            "type": v.get("VolumeType"),
            "created": str(v.get("CreateTime", ""))[:19],
            "name": name_tag
        })
    return volumes


def get_stale_efs_file_systems(region: str) -> List[Dict[str, Any]]:
    """Fetches all EFS file systems that are unused or tagged with gitea in a region."""
    data = run_aws_command(["efs", "describe-file-systems"], region)
    if not data or "FileSystems" not in data:
        return []
    
    stale_efs = []
    for fs in data["FileSystems"]:
        fs_id = fs.get("FileSystemId")
        name = fs.get("Name", "-")
        mount_targets = fs.get("NumberOfMountTargets", 0)
        creation_token = fs.get("CreationToken", "")
        
        # Consider stale if 0 mount targets OR matches gitea
        if mount_targets == 0 or "gitea" in name.lower() or "gitea" in creation_token.lower():
            stale_efs.append({
                "region": region,
                "id": fs_id,
                "name": name,
                "mount_targets": mount_targets,
                "state": fs.get("LifeCycleState", "unknown")
            })
    return stale_efs


def delete_ebs_volume(volume_id: str, region: str) -> bool:
    """Deletes an unattached EBS volume."""
    try:
        subprocess.run(
            ["aws", "ec2", "delete-volume", "--volume-id", volume_id, "--region", region],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        return True
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"   ⚠️ Failed to delete volume {volume_id} in {region}: {e.stderr.decode('utf-8') if isinstance(e.stderr, bytes) else e.stderr}\n")
        return False


def delete_efs_file_system(fs_id: str, region: str) -> bool:
    """Deletes an EFS file system, removing access points and mount targets first."""
    # 1. Delete Access Points
    ap_data = run_aws_command(["efs", "describe-access-points", "--file-system-id", fs_id], region)
    if ap_data and "AccessPoints" in ap_data:
        for ap in ap_data["AccessPoints"]:
            ap_id = ap["AccessPointId"]
            print(f"     - Deleting Access Point: {ap_id}...")
            run_aws_command(["efs", "delete-access-point", "--access-point-id", ap_id], region)

    # 2. Delete Mount Targets
    mt_data = run_aws_command(["efs", "describe-mount-targets", "--file-system-id", fs_id], region)
    if mt_data and "MountTargets" in mt_data and len(mt_data["MountTargets"]) > 0:
        for mt in mt_data["MountTargets"]:
            mt_id = mt["MountTargetId"]
            print(f"     - Deleting Mount Target: {mt_id}...")
            run_aws_command(["efs", "delete-mount-target", "--mount-target-id", mt_id], region)
        
        print("     ⏳ Waiting for Mount Target network interfaces to detach...")
        while True:
            check = run_aws_command(["efs", "describe-mount-targets", "--file-system-id", fs_id], region)
            if not check or len(check.get("MountTargets", [])) == 0:
                print("     ✅ Mount targets detached.")
                break
            time.sleep(4)

    # 3. Delete File System
    print(f"     - Deleting File System {fs_id}...")
    run_aws_command(["efs", "delete-file-system", "--file-system-id", fs_id], region)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Scan ALL AWS regions to clean up stale, unattached EBS volumes and unused EFS file systems."
    )
    parser.add_argument(
        "--region",
        default=None,
        help="Scan only a specific AWS region (e.g., ap-south-1). If omitted, scans ALL enabled regions."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and list unused resources without deleting anything."
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Delete without interactive confirmation prompt."
    )

    args = parser.parse_args()

    # 1. Verify AWS authentication
    auth_check = run_aws_command(["sts", "get-caller-identity"])
    if not auth_check:
        sys.stderr.write("❌ Error: AWS authentication failed. Configure your credentials.\n")
        sys.exit(1)

    account_id = auth_check.get("Account", "Unknown")

    if args.region:
        target_regions = [args.region]
        scan_mode = f"Single Region: {args.region}"
    else:
        print("🔍 Querying all enabled AWS regions for account", account_id, "...")
        target_regions = get_all_aws_regions()
        scan_mode = f"ALL Regions ({len(target_regions)} regions)"

    print("=" * 75)
    print(f"🌍 AWS Global Storage Cleanup Utility (Python)")
    print(f"🔑 AWS Account: {account_id} | Scan Scope: {scan_mode}")
    print("=" * 75)

    all_ebs_volumes: List[Dict[str, Any]] = []
    all_efs_filesystems: List[Dict[str, Any]] = []

    print("\n🔍 Scanning across regions for unattached EBS volumes and stale EFS...")
    for idx, reg in enumerate(target_regions, 1):
        print(f"  [{idx:02d}/{len(target_regions):02d}] Scanning region: {reg}...", end="\r", flush=True)
        
        ebs = get_unattached_ebs_volumes(reg)
        efs = get_stale_efs_file_systems(reg)

        if ebs:
            all_ebs_volumes.extend(ebs)
        if efs:
            all_efs_filesystems.extend(efs)

    print(" " * 60, end="\r")  # Clear scanning progress line
    print("✅ Regional scans complete.\n")

    # --------------------------------------------------------------------------
    # 2. Present Findings
    # --------------------------------------------------------------------------
    total_ebs_gb = sum(v["size"] for v in all_ebs_volumes) if all_ebs_volumes else 0

    if all_ebs_volumes:
        print(f"📦 Found {len(all_ebs_volumes)} Unattached EBS Volume(s) ({total_ebs_gb} GiB total):")
        print("-" * 75)
        print(f"{'REGION':<16} {'VOLUME ID':<22} {'SIZE':<8} {'TYPE':<8} {'NAME / TAG'}")
        print("-" * 75)
        for v in all_ebs_volumes:
            print(f"{v['region']:<16} {v['id']:<22} {str(v['size']) + 'G':<8} {v['type']:<8} {v['name']}")
        print("-" * 75)
    else:
        print("✅ EBS Volumes: No unattached volumes found across any scanned region.")

    print("")
    if all_efs_filesystems:
        print(f"📁 Found {len(all_efs_filesystems)} Stale / Orphaned EFS File System(s):")
        print("-" * 75)
        print(f"{'REGION':<16} {'FILE SYSTEM ID':<24} {'NAME':<20} {'MOUNTS'}")
        print("-" * 75)
        for fs in all_efs_filesystems:
            print(f"{fs['region']:<16} {fs['id']:<24} {fs['name']:<20} {str(fs['mount_targets'])}")
        print("-" * 75)
    else:
        print("✅ EFS File Systems: No stale EFS instances found across any scanned region.")

    # --------------------------------------------------------------------------
    # 3. Check if anything to delete
    # --------------------------------------------------------------------------
    if not all_ebs_volumes and not all_efs_filesystems:
        print("\n🎉 Everything is clean! Zero orphaned EBS volumes or EFS file systems found globally.")
        sys.exit(0)

    if args.dry_run:
        print("\n🔍 Dry-run mode enabled. No resources were deleted.")
        sys.exit(0)

    # --------------------------------------------------------------------------
    # 4. Confirmation
    # --------------------------------------------------------------------------
    if not args.force:
        print("\n" + "=" * 75)
        print(f"⚠️  CONFIRM DELETION: {len(all_ebs_volumes)} EBS Volume(s) & {len(all_efs_filesystems)} EFS File System(s)")
        print("=" * 75)
        try:
            confirm = input("Are you sure you want to permanently delete these resources? (type 'yes' to confirm): ").strip()
        except EOFError:
            confirm = "no"

        if confirm.lower() != "yes":
            print("❌ Deletion cancelled by user. No resources were deleted.")
            sys.exit(0)

    # --------------------------------------------------------------------------
    # 5. Execute Deletions
    # --------------------------------------------------------------------------
    if all_ebs_volumes:
        print("\n🗑️  Deleting unattached EBS Volumes...")
        for v in all_ebs_volumes:
            print(f"  -> [{v['region']}] Deleting EBS Volume: {v['id']} ({v['size']} GiB)...", end="", flush=True)
            if delete_ebs_volume(v["id"], v["region"]):
                print(" ✅ Deleted")
            else:
                print(" ❌ Error")

    if all_efs_filesystems:
        print("\n🗑️  Deleting stale EFS File Systems...")
        for fs in all_efs_filesystems:
            print(f"  -> [{fs['region']}] Processing EFS: {fs['id']} ({fs['name']})...")
            delete_efs_file_system(fs["id"], fs["region"])
            print(f"  ✅ EFS {fs['id']} deleted.")

    print("\n" + "=" * 75)
    print("🎉 Global Cleanup Complete! All orphaned storage resources have been deleted.")
    print("=" * 75)


if __name__ == "__main__":
    main()
