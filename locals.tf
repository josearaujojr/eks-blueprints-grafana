locals {
  name            = "eks-lab"
  region          = data.aws_region.current.name
  cluster_version = "1.30"

  account_id = "058264204627"
  username_1 = "josealmino"
  username_2 = "josealmino"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  node_group_name   = "managed-ondemand"
  node_group_name_2 = "managed-ondemand-2"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
    "karpenter.sh/discovery" = local.name
  }
}
