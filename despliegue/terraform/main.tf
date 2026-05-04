module "network" {
    source = "./modules/network"
}

module "storage" {
    source = "./modules/storage"
    private_data_subnet_ids = module.network.private_data_subnet_ids
    db_security_group_id = module.network.private_sg_id_db
}

module "iam" {
  source = "./modules/iam"

  db_arn            = module.storage.db_arn
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

module "eks" {
    source = "./modules/eks"

    subnets_app = module.network.private_app_subnet_ids
    eks_cluster_ARN_role = module.iam.eks-cluster-role
    eks-worker-node-ARN-role = module.iam.eks-worker-node-role

}

module "ecr" {
    source = "./modules/ecr"
}

output "db_secret_arn_final" {
  value = module.storage.db_arn 
}