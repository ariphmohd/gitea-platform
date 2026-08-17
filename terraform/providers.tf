terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend configuration for remote state in S3 and DynamoDB state locking
  # Uncomment and customize this block for production team usage:
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "gitea-platform/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "your-terraform-lock-table"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.tags,
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "Terraform"
      }
    )
  }
}
