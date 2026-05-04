variable "subnets_app" {
    type = list(string)
    description = "Subnets id's (app = eks)"
}

variable "eks_cluster_ARN_role" {
    type = string
    description = "ARN of eks cluster role"
}

variable "eks-worker-node-ARN-role" {
    type = string
    description = "ARN of eks worker node role"

}