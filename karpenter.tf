##################### ROLE KARPENTER NODE

# Define o documento de política de trust
data "aws_iam_policy_document" "karpenter_node_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Cria a role do Karpenter para os nodes
resource "aws_iam_role" "karpenter_node_role" {
  name               = "KarpenterNodeRole-${local.name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_trust_policy.json
}

# Anexa a política AmazonEKSWorkerNodePolicy
resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker_policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Anexa a política AmazonEKS_CNI_Policy
resource "aws_iam_role_policy_attachment" "karpenter_node_eks_cni_policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Anexa a política AmazonEC2ContainerRegistryReadOnly
resource "aws_iam_role_policy_attachment" "karpenter_node_ecr_readonly_policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Anexa a política AmazonSSMManagedInstanceCore
resource "aws_iam_role_policy_attachment" "karpenter_node_ssm_policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

##################### ROLE KARPENTER CONTROLLER

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "karpenter_controller_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.oidc.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${data.aws_iam_openid_connect_provider.oidc.url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${data.aws_iam_openid_connect_provider.oidc.url}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }
  }
}


# Anexa a policy AmazonEC2FullAccess à role do Karpenter Controller
resource "aws_iam_role_policy_attachment" "karpenter_ec2_full_access" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# Cria a role do Karpenter Controller
resource "aws_iam_role" "karpenter_controller_role" {
  name               = "KarpenterControllerRole-${local.name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_trust_policy.json
}

resource "aws_iam_policy" "karpenter_policy" {
  name        = "KarpenterPolicy-${local.name}"
  description = "Policy for Karpenter nodes to interact with EC2 and other services"
  policy      = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeAvailabilityZones",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/nodepool": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::${local.account_id}:role/KarpenterNodeRole-${local.name}",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:us-east-2:${local.account_id}:cluster/${local.name}",
            "Sid": "EKSClusterEndpointLookup"
        },
        {
            "Sid": "AllowScopedInstanceProfileCreationActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
                "iam:CreateInstanceProfile"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:RequestTag/kubernetes.io/cluster/${local.name}": "owned",
                    "aws:RequestTag/topology.kubernetes.io/region": "us-east-2"
                },
                "StringLike": {
                    "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
            }
        },
        {
            "Sid": "AllowScopedInstanceProfileTagActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
                "iam:TagInstanceProfile"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/kubernetes.io/cluster/${local.name}": "owned",
                    "aws:ResourceTag/topology.kubernetes.io/region": "us-east-2",
                    "aws:RequestTag/kubernetes.io/cluster/${local.name}": "owned",
                    "aws:RequestTag/topology.kubernetes.io/region": "us-east-2"
                },
                "StringLike": {
                    "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
                    "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
            }
        },
        {
            "Sid": "AllowScopedInstanceProfileActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeleteInstanceProfile"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/kubernetes.io/cluster/${local.name}": "owned",
                    "aws:ResourceTag/topology.kubernetes.io/region": "us-east-2"
                },
                "StringLike": {
                    "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
                }
            }
        },
        {
            "Sid": "AllowInstanceProfileReadActions",
            "Effect": "Allow",
            "Resource": "*",
            "Action": "iam:GetInstanceProfile"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "karpenter_policy_attachment" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = aws_iam_policy.karpenter_policy.arn

  depends_on = [
    aws_iam_role.karpenter_controller_role,
    aws_iam_policy.karpenter_policy
  ]
}

provider "aws" {
    region = "us-east-1"
    alias  = "ecr"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

resource "helm_release" "karpenter" {
  depends_on                 = [module.eks_blueprints]
  create_namespace       = true
  name                            = "karpenter"
  repository                     = "oci://public.ecr.aws/karpenter"
  repository_username   = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password    = data.aws_ecrpublic_authorization_token.token.password
  version                          = "1.0.7"
  chart                             = "karpenter"
  namespace                   = "karpenter"


  set {
    name  = "settings.clusterName"
    value = module.eks_blueprints.eks_cluster_id
  }

  set {
    name  = "settings.clusterEndpoint"
    value = module.eks_blueprints.eks_cluster_endpoint
  }
}

data "http" "karpenter_nodepools" {
  url = "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.0.7/pkg/apis/crds/karpenter.sh_nodepools.yaml"
}

data "http" "karpenter_ec2nodeclasses" {
  url = "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.0.7/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml"
}

data "http" "karpenter_nodeclaims" {
  url = "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.0.7/pkg/apis/crds/karpenter.sh_nodeclaims.yaml"
}

resource "kubectl_manifest" "karpenter_nodepools_git" {
  yaml_body = data.http.karpenter_nodepools.body

  depends_on = [
    module.eks_blueprints
  ]
}

resource "kubectl_manifest" "karpenter_ec2nodeclasses" {
  yaml_body = data.http.karpenter_ec2nodeclasses.body

  depends_on = [
    module.eks_blueprints
  ]
}

resource "kubectl_manifest" "karpenter_nodeclaims" {
  yaml_body = data.http.karpenter_nodeclaims.body

  depends_on = [
    module.eks_blueprints
  ]
}

resource "kubectl_manifest" "install_nodepool" {
  yaml_body = <<-EOT
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 2160h
  limits:
    cpu: 90000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    EOT

  depends_on = [
    module.eks_blueprints
  ]
}

resource "kubectl_manifest" "install_ec2nodeclass" {
  yaml_body = <<-EOT
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2 # Amazon Linux 2
  role: "KarpenterNodeRole-${local.name}" # replace with your cluster name
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${local.name}" # replace with your cluster name
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${local.name}" # replace with your cluster name
  amiSelectorTerms:
    - id: "ami-08ff7fe07b783480f"
    - id: "ami-0765d74c8803057e8"
    EOT

  depends_on = [
    module.eks_blueprints
  ]
}

# provider "aws" {
#     region = "us-east-1"
#     alias  = "ecr"
# }

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.ecr
# }

# module "karpenter" {
#   source = "terraform-aws-modules/eks/aws//modules/karpenter"

#   cluster_name = module.eks_blueprints.eks_cluster_id

#   enable_v1_permissions = true

#   enable_pod_identity             = true
#   create_pod_identity_association = true

#   # Attach additional IAM policies to the Karpenter node IAM role
#   node_iam_role_additional_policies = {
#     AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   }
# }

# ###############################################################################
# # Karpenter Helm
# ###############################################################################
# resource "helm_release" "karpenter" {
#     provider = helm.eks
#   namespace           = "kube-system"
#   name                = "karpenter"
#   repository          = "oci://public.ecr.aws/karpenter"
#   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
#   repository_password = data.aws_ecrpublic_authorization_token.token.password
#   chart               = "karpenter"
#   version             = "1.0.0"
#   wait                = false

#   values = [
#     <<-EOT
#     serviceAccount:
#       name: ${module.karpenter.service_account}
#     settings:
#       clusterName: ${module.eks_blueprints.eks_cluster_id}
#       clusterEndpoint: ${module.eks_blueprints.eks_cluster_endpoint}
#       interruptionQueue: ${module.karpenter.queue_name}
#     EOT
#   ]
# }

# ###############################################################################
# # Karpenter Kubectl
# ###############################################################################
# resource "kubectl_manifest" "karpenter_node_pool" {
#     provider = kubectl.eks
#   yaml_body = <<-YAML
#     apiVersion: karpenter.sh/v1beta1
#     kind: NodePool
#     metadata:
#       name: default
#     spec:
#       template:
#         spec:
#           nodeClassRef:
#             name: default
#           requirements:
#             - key: "karpenter.k8s.aws/instance-category"
#               operator: In
#               values: ["c", "m", "r"]
#             - key: "karpenter.k8s.aws/instance-cpu"
#               operator: In
#               values: ["4", "8", "16", "32"]
#             - key: "karpenter.k8s.aws/instance-hypervisor"
#               operator: In
#               values: ["nitro"]
#             - key: "karpenter.k8s.aws/instance-generation"
#               operator: Gt
#               values: ["2"]
#       limits:
#         cpu: 1000
#       disruption:
#         consolidationPolicy: WhenEmpty
#         consolidateAfter: 30s
#   YAML

#   depends_on = [
#     kubectl_manifest.karpenter_node_class
#   ]
# }

# resource "kubectl_manifest" "karpenter_node_class" {
#     provider = kubectl.eks
#   yaml_body = <<-YAML
#     apiVersion: karpenter.k8s.aws/v1beta1
#     kind: EC2NodeClass
#     metadata:
#       name: default
#     spec:
#       amiFamily: AL2023
#       role: ${module.karpenter.node_iam_role_name}
#       subnetSelectorTerms:
#         - tags:
#             karpenter.sh/discovery: ${local.name}
#       securityGroupSelectorTerms:
#         - tags:
#             karpenter.sh/discovery: ${local.name}
#       tags:
#         karpenter.sh/discovery: ${local.name}
#   YAML

#   depends_on = [
#     helm_release.karpenter
#   ]
# }