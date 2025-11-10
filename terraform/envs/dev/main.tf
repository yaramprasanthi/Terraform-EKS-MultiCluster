provider "aws" { region = "ap-south-1" }

module "vpc" {
  source       = "../../modules/vpc"
  cluster_name = "dev-eks-cluster"
  region       = "ap-south-1"
}

module "eks" {
  source       = "../../modules/eks"
  cluster_name = "dev-eks-cluster"
  vpc_id       = module.vpc.vpc_id
  subnets      = module.vpc.subnets
}

module "node_group" {
  source           = "../../modules/node_group"
  cluster_name     = "dev-eks-cluster"
  cluster_role_arn = module.eks.cluster_arn
  subnets          = module.vpc.subnets
}
