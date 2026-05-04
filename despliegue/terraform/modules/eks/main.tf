

resource "aws_eks_cluster" "cluster_app" {
  name     = "cluster_app"

  role_arn = var.eks_cluster_ARN_role
  version  = "1.31"

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids = var.subnets_app
  }
}

resource "aws_eks_node_group" "eks-node-group" {
  cluster_name    = aws_eks_cluster.cluster_app.name
  node_group_name = "ng-cluster"
  node_role_arn   = var.eks-worker-node-ARN-role
  subnet_ids      = var.subnets_app

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster_app.identity[0].oidc[0].issuer
}

# 2. Creamos el proveedor de identidad en IAM vinculándolo al clúster
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster_app.identity[0].oidc[0].issuer
}

# Creamos la entrada en la lista del clúster para el usuario
resource "aws_eks_access_entry" "venganza_admin" {
  cluster_name      = aws_eks_cluster.cluster_app.name
  principal_arn     = "arn:aws:iam::622370466117:user/eks-venganza"
  type              = "STANDARD"
}

# Ponemos como admin del clúster a esa entrada
resource "aws_eks_access_policy_association" "venganza_admin_policy" {
  cluster_name  = aws_eks_cluster.cluster_app.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.venganza_admin.principal_arn

  access_scope {
    type = "cluster"
  }
}