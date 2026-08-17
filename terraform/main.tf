# ==============================================================================
# 1. VPC Module (2 AZs in ap-south-1 for Cost Optimization)
# ==============================================================================

module "vpc" {
  source = "./modules/vpc"

  environment           = var.environment
  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  cluster_name          = var.cluster_name
  tags                  = var.tags
}

# ==============================================================================
# 2. EKS Cluster Module (Graviton2 t4g.small ARM64)
# ==============================================================================

module "eks" {
  source = "./modules/eks"

  environment         = var.environment
  project_name        = var.project_name
  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  ami_type            = var.ami_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  tags                = var.tags
}

# ==============================================================================
# 3. RDS PostgreSQL Module (Free-Tier db.t4g.micro Single-AZ)
# ==============================================================================

module "rds" {
  source = "./modules/rds"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.vpc.vpc_id
  database_subnet_group_name = module.vpc.database_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id
  private_subnet_cidrs       = var.private_subnet_cidrs
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  max_allocated_storage      = var.db_max_allocated_storage
  db_name                    = var.db_name
  db_username                = var.db_username
  multi_az                   = var.db_multi_az
  backup_retention_period    = var.db_backup_retention_period
  tags                       = var.tags
}

# ==============================================================================
# 4. Storage Module (Amazon EFS One Zone & Amazon S3)
# ==============================================================================

module "storage" {
  source = "./modules/storage"

  environment                = var.environment
  project_name               = var.project_name
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  private_subnet_cidrs       = var.private_subnet_cidrs
  enable_one_zone            = var.enable_efs_one_zone
  availability_zone_name     = var.efs_availability_zone
  eks_node_security_group_id = module.eks.node_security_group_id
  tags                       = var.tags
}

# ==============================================================================
# 5. IAM & IRSA Module
# ==============================================================================

module "iam" {
  source = "./modules/iam"

  environment            = var.environment
  project_name           = var.project_name
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url
  s3_bucket_arn          = module.storage.s3_bucket_arn
  db_password_secret_arn = module.rds.db_password_secret_arn
  tags                   = var.tags
}
