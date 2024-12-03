# eks-blueprints-grafana

terraform init
terraform plan
terraform apply -target=module.vpc -auto-approve
terraform apply -target=module.eks_blueprints -auto-approve
terraform apply -target=module.kubernetes_addons -auto-approve
terraform apply -auto-approve

terraform destroy -target=module.kubernetes_addons -auto-approve
terraform destroy -target=module.eks_blueprints -auto-approve
terraform destroy -target=module.vpc -auto-approve
terraform destroy -auto-approve