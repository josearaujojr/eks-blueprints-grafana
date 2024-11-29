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
