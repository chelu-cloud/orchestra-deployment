output "eks-cluster-role" {
    description = "Cluster role ARN"
    value = aws_iam_role.eks-cluster-role.arn
}

output "eks-worker-node-role" {
    description = "Worker node role ARN"
    value = aws_iam_role.eks-worker-node-role.arn
}

output "app_role" {
    description = "App role ARN"
    value = aws_iam_role.kubernetes-oidc-role.arn
}