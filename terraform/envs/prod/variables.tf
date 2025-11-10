##################################################
# Input Variables
##################################################

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "prod-eks-cluster"
}

variable "region" {
  description = "AWS region for EKS cluster"
  type        = string
  default     = "ap-south-1"
}

