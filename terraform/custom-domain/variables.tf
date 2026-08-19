# ==============================================================================
# Variables for Custom Domain & Route 53 Module
# ==============================================================================

variable "aws_region" {
  description = "The AWS Region where the infrastructure is deployed"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, dev)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project identifier"
  type        = string
  default     = "gitea"
}

variable "domain_name" {
  description = "The root domain name registered in GoDaddy (e.g. ariphmohd.shop)"
  type        = string
  default     = "ariphmohd.shop"
}

variable "subdomains" {
  description = "List of subdomains to configure"
  type        = list(string)
  default     = ["gitea", "grafana", "argocd"]
}

variable "alb_dns_name" {
  description = "The DNS name of the AWS Application Load Balancer (leave blank if setting up before ALB)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to domain resources"
  type        = map(string)
  default = {
    Environment = "prod"
    Application = "gitea-platform"
    Module      = "custom-domain"
    ManagedBy   = "Terraform"
  }
}
