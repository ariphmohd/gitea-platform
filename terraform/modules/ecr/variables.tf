# ==============================================================================
# Variables for Amazon ECR Module
# ==============================================================================

variable "repository_name" {
  description = "Name of the Amazon ECR repository"
  type        = string
  default     = "gitea-custom"
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain in ECR lifecycle policy"
  type        = number
  default     = 10
}

variable "scan_on_push" {
  description = "Indicates whether images are scanned after being pushed to the repository"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project identifier"
  type        = string
  default     = "gitea"
}

variable "tags" {
  description = "Common tags applied to the ECR repository"
  type        = map(string)
  default = {
    Environment = "prod"
    Application = "gitea-custom"
    ManagedBy   = "Terraform"
  }
}
