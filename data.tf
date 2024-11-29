# encontra o usuário atualmente em uso pela AWS
data "aws_caller_identity" "current" {}

# region na qual a solução será implantada
data "aws_region" "current" {}

# azs a serem usadas em nossa solução
data "aws_availability_zones" "available" {
  state = "available"
}

# detals do cluster EKS
data "aws_eks_cluster" "cluster" {
  name = module.eks_blueprints.eks_cluster_id
}

# detals de autenticação do cluster EKS
data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

# openid cluster eks
data "aws_iam_openid_connect_provider" "cluster" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}