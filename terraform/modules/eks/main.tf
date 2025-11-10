variable "cluster_name" {}
variable "vpc_id" {}
variable "subnets" {}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  vpc_config {
    subnet_ids         = var.subnets
    security_group_ids = []
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

output "cluster_name" { value = aws_eks_cluster.eks_cluster.name }
output "cluster_arn"  { value = aws_eks_cluster.eks_cluster.arn }
