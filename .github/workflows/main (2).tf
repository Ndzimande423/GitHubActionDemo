terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"

  backend "s3" {
    bucket         = "cryptex-aws-terraform-state-bucket"
    key            = "cryptex/aws/core/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "cryptex-aws-terraform-locks"  # Optional, for state locking
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

module "vpc" {
  source = "./core/vpc"
  region = var.region
  environment = var.environment
  project = var.project
  deploy_version = var.deploy_version
  orchestrator = var.orchestrator
}

module "state" {
  source = "./core/state"
  environment = var.environment
  project = var.project
  deploy_version = var.deploy_version
  orchestrator = var.orchestrator
}

module "ALB" {
  source = "./resources/ALB"
  certificate_arn = var.certificate_arn
  subnet_ids = module.vpc.public_subnets
  service_name = "swiftclaim"
  security_group_ids = module.vpc.security_group_ids
 
  environment = var.environment
  project = var.project
  deploy_version = var.deploy_version
  orchestrator = var.orchestrator
}

module "ECS" {
  source = "./resources/ECS"
 
  service_name = "swiftclaim"
  environment = var.environment
  project = var.project
  deploy_version = var.deploy_version
  orchestrator = var.orchestrator
}

module "routes" {
  source = "./resources/swiftclaim-routes"
  vpc_id = module.vpc.vpc_id
  https_listener_arn = module.ALB.https_listener_arn
  security_group_ids = module.vpc.security_group_ids
  subnet_ids = module.vpc.private_subnets
 
}

module "services " {
  source = "./resources/swiftclaim-service"

  vpc_id = module.vpc.vpc_id
  alb_security_group_id = module.vpc.alb_security_group_id
  xmedical_admin_task_definition = module.ECS.xmedical_admin_task_definition
  xmedical_api_task_definition = module.ECS.xmedical_api_task_definition
  xmedical_admin_target_group_arn = module.ECS.xmedical_admin_target_group_arn
  xmedical_api_target_group_arn = module.ECS.xmedical_api_target_group_arn

  keycloak_task_definition = module.ECS.keycloak_task_definition
  ecs_cluster = module.ECS.ecs_cluster_id
  keycloak_manage_target_group_arn = module.routes.kecloak_manage_target_group_arn
  keycloak_target_group_arn = module.routes.keycloak_target_group_arn
  
  subnets = module.vpc.private_subnets
}