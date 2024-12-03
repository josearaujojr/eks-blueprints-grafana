# eks-blueprints-grafana

terraform init<br/>
terraform plan<br/>
terraform apply -target=module.vpc -auto-approve<br/>
terraform apply -target=module.eks_blueprints -auto-approve<br/>
terraform apply -target=module.kubernetes_addons -auto-approve<br/>
terraform apply -auto-approve<br/>

########<br/>

terraform destroy -target=module.kubernetes_addons -auto-approve<br/>
terraform destroy -target=module.eks_blueprints -auto-approve<br/>
terraform destroy -target=module.vpc -auto-approve<br/>
terraform destroy -auto-approve<br/>