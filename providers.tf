terraform {
  required_version = ">= 1.0.1"

  required_providers {
    # Provedor AWS para interagir com os serviços da AWS
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    # Provedor Kubernetes para gerenciar recursos do Kubernetes
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    # Provedor Helm para gerenciar charts do Helm
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4.1"
    }
    # Provedor Kubectl para aplicar configurações do Kubernetes
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}

provider "helm" {
  alias = "eks"
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # Requer o AWS CLI instalado localmente
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

provider "kubectl" {
  alias = "eks"
  apply_retry_count      = 5
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Requer o AWS CLI instalado localmente
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}
