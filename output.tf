# ID da VPC
output "vpc_id" {
  description = "O ID da VPC"
  value       = module.vpc.vpc_id
}

# Comando para configurar o kubectl
output "configure_kubectl" {
  description = "Configure o kubectl: certifique-se de estar logado com o perfil AWS correto e execute o seguinte comando para atualizar seu kubeconfig"
  value       = module.eks_blueprints.configure_kubectl
}

# Endpoint do cluster EKS
output "eks_cluster_endpoint" {
  description = "O endpoint do cluster EKS"
  value       = module.eks_blueprints.eks_cluster_endpoint
}

# Nome do cluster EKS
output "eks_cluster_name" {
  description = "O nome do cluster EKS"
  value       = module.eks_blueprints.eks_cluster_id
}

# ARN do cluster EKS
output "eks_cluster_arn" {
  description = "O ARN do cluster EKS"
  value       = module.eks_blueprints.eks_cluster_arn
}
