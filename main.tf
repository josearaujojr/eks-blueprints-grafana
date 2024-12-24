provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.32.1"

  cluster_name = local.name

  # config obrigatória do VPC e Subnet do cluster EKS
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  # var do plano de controle do EKS
  cluster_version = local.cluster_version

  # list de funções adicionais com permissões de administrador no cluster
  map_roles = [
    {
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TeamRole"
      username = "ops-role"
      groups   = ["system:masters"]
    },
    # {
    #   rolearn  = "arn:aws:iam::${local.account_id}:role/KarpenterIRSA-eks-lab"
    #   username = "system:node:{{EC2PrivateDNSName}}"
    #   groups   = ["system:bootstrappers", "system:nodes"]
    # },
    {
      rolearn  = "arn:aws:iam::${local.account_id}:role/eks-admin"
      username = "eks-admin"
      groups   = ["system:masters"]
    }
  ]

  # list de usuários mapeados
  map_users = [
    {
      userarn  = data.aws_caller_identity.current.arn
      username = local.username_1
      groups   = ["system:masters", "eks-console-dashboard-full-access-group"]
    },
    {
      userarn  = "arn:aws:iam::${local.account_id}:user/${local.username_2}"
      username = local.username_2
      groups   = ["system:masters", "eks-console-dashboard-full-access-group"]
    },
    {
      userarn  = "arn:aws:iam::${local.account_id}:root"
      username = "root"
      groups   = ["system:masters", "eks-console-dashboard-full-access-group"]
    }
  ]

  # EKS MANAGED NODE GROUPS
  managed_node_groups = {
    T3_MEDIUM = {
      node_group_name = local.node_group_name
      instance_types  = ["t3.medium"]
      subnet_ids      = module.vpc.private_subnets
      min_size        = 2
      max_size        = 10
      desired_size    = 2
    }
  }

  # teams
  platform_teams = {
    admin = {
      users = [
        data.aws_caller_identity.current.arn,
        "arn:aws:iam::${local.account_id}:root"
      ]
    }
  }

  tags = local.tags
}

output "debug_managed_node_group_arn" {
  value = module.eks_blueprints.managed_node_group_arn
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.14.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
    "karpenter.sh/discovery" = null
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

  tags = local.tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.20.0"

  cluster_name                    = local.name
  irsa_oidc_provider_arn          = module.eks_blueprints.eks_oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  create_iam_role      = false
  iam_role_arn         = "arn:aws:iam::058264204627:role/eks-lab-managed-ondemand"
  irsa_use_name_prefix = false

  tags = local.tags
}

provider "aws" {
    region = "us-east-1"
    alias  = "ecr"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "v0.31.3"

  set {
    name  = "settings.aws.clusterName"
    value = local.name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks_blueprints.eks_cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.irsa_arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter.instance_profile_name
  }

  set {
    name  = "settings.aws.interruptionQueueName"
    value = module.karpenter.queue_name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"] #"spot"
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        # - key: "node.kubernetes.io/instance-type"
        #   operator: In
        #   values: ["c5.large","c5a.large", "c5ad.large", "c5d.large", "c6i.large", "t2.medium", "t3.medium", "t3a.medium"]
      limits:
        resources:
          cpu: 1000
      providerRef:
        name: default
      ttlSecondsAfterEmpty: 30
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_template" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: default
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${local.name}
      securityGroupSelector:
        karpenter.sh/discovery: ${local.name}
      tags:
        karpenter.sh/discovery: ${local.name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# Manifestos
resource "kubectl_manifest" "rbac" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: eks-console-dashboard-full-access-clusterrole
    rules:
    - apiGroups:
      - ""
      resources:
      - nodes
      - namespaces
      - pods
      - configmaps
      - endpoints
      - events
      - limitranges
      - persistentvolumeclaims
      - podtemplates
      - replicationcontrollers
      - resourcequotas
      - secrets
      - serviceaccounts
      - services
      verbs:
      - get
      - list
    - apiGroups:
      - apps
      resources:
      - deployments
      - daemonsets
      - statefulsets
      - replicasets
      verbs:
      - get
      - list
    - apiGroups:
      - batch
      resources:
      - jobs
      - cronjobs
      verbs:
      - get
      - list
    - apiGroups:
      - coordination.k8s.io
      resources:
      - leases
      verbs:
      - get
      - list
    - apiGroups:
      - discovery.k8s.io
      resources:
      - endpointslices
      verbs:
      - get
      - list
    - apiGroups:
      - events.k8s.io
      resources:
      - events
      verbs:
      - get
      - list
    - apiGroups:
      - extensions
      resources:
      - daemonsets
      - deployments
      - ingresses
      - networkpolicies
      - replicasets
      verbs:
      - get
      - list
    - apiGroups:
      - networking.k8s.io
      resources:
      - ingresses
      - networkpolicies
      verbs:
      - get
      - list
    - apiGroups:
      - policy
      resources:
      - poddisruptionbudgets
      verbs:
      - get
      - list
    - apiGroups:
      - rbac.authorization.k8s.io
      resources:
      - rolebindings
      - roles
      verbs:
      - get
      - list
    - apiGroups:
      - storage.k8s.io
      resources:
      - csistoragecapacities
      verbs:
      - get
      - list
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: eks-console-dashboard-full-access-binding
    subjects:
    - kind: Group
      name: eks-console-dashboard-full-access-group
      apiGroup: rbac.authorization.k8s.io
    roleRef:
      kind: ClusterRole
      name: eks-console-dashboard-full-access-clusterrole
      apiGroup: rbac.authorization.k8s.io
  YAML

  depends_on = [
    module.eks_blueprints
  ]
}

## ADDONS

module "kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.32.1/modules/kubernetes-addons"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  enable_aws_load_balancer_controller  = true
  enable_amazon_eks_aws_ebs_csi_driver = true
  enable_metrics_server                = true
  enable_kube_prometheus_stack         = true

  kube_prometheus_stack_helm_config = {
    name = "kube-prometheus-stack" # (Obrigatório) Nome da release.
    #repository = "https://prometheus-community.github.io/helm-charts" # (Opcional) URL do repositório onde localizar o chart solicitado.
    chart     = "kube-prometheus-stack" # (Obrigatório) chart a ser instalado.
    namespace = "kube-prometheus-stack" # (Opcional) namespace para instalar a release.
    values     = [<<-EOF
      defaultRules:
        create: true
        rules:
          etcd: false
          kubeScheduler: false
      kubeControllerManager:
        enabled: false
      kubeEtcd:
        enabled: false
      kubeScheduler:
        enabled: false
      prometheus:
        prometheusSpec:
          storageSpec:
            volumeClaimTemplate:
              spec:
                accessModes:
                - ReadWriteOnce
                resources:
                  requests:
                    storage: 20Gi
                storageClassName: gp2
        enabled: true
        ## Configuration for Prometheus service
        ##
        service:
          annotations: {}
          labels: {}
          clusterIP: ""
          port: 9090
          ## To be used with a proxy extraContainer port
          targetPort: 9090
          ## List of IP addresses at which the Prometheus server service is available
          ## Ref: https://kubernetes.io/docs/user-guide/services/#external-ips
          ##
          externalIPs: []
          ## Port to expose on each node
          ## Only used if service.type is 'NodePort'
          ##
          nodePort: 30090
          type: NodePort


      # Adicionando Grafana Dashboards
      # Projeto: https://github.com/dotdc/grafana-dashboards-kubernetes
      # Artigo: https://medium.com/@dotdc/a-set-of-modern-grafana-dashboards-for-kubernetes-4b989c72a4b2

      grafana:
        # Provision grafana-dashboards-kubernetes
        dashboardProviders:
          dashboardproviders.yaml:
            apiVersion: 1
            providers:
            - name: 'grafana-dashboards-kubernetes'
              orgId: 1
              folder: 'Kubernetes'
              type: file
              disableDeletion: true
              editable: true
              options:
                path: /var/lib/grafana/dashboards/grafana-dashboards-kubernetes
        dashboards:
          grafana-dashboards-kubernetes:
            k8s-system-api-server:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-api-server.json
              token: ''
            k8s-system-coredns:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-coredns.json
              token: ''
            k8s-views-global:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json
              token: ''
            k8s-views-namespaces:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-namespaces.json
              token: ''
            k8s-views-nodes:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-nodes.json
              token: ''
            k8s-views-pods:
              url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-pods.json
              token: ''
        sidecar:
          dashboards:
            enabled: true
            defaultFolderName: "General"
            label: grafana_dashboard
            labelValue: "1"
            folderAnnotation: grafana_folder
            searchNamespace: ALL
            provider:
              foldersFromFilesStructure: true
        grafana:
          enabled: true
          datasources:
            datasources.yaml:
              apiVersion: 1
              datasources:
              - name: Loki
                type: loki
                url: http://loki:3100
                access: proxy
                isDefault: false
    EOF
    ]
  }

  enable_ingress_nginx = true
  ingress_nginx_helm_config = {
    name       = "ingress-nginx"
    repository = "https://kubernetes.github.io/ingress-nginx"
    chart      = "ingress-nginx"
    version    = "4.11.3"
    namespace  = "ingress-nginx"

    values = [
      <<-EOF
      controller:
        replicaCount: 2
        service:
          type: LoadBalancer
          annotations:
            service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
            service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
            service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
        metrics:
          enabled: true
        resources:
          requests:
            cpu: 100m
            memory: 90Mi
      EOF
    ]  
  }

  depends_on = [
    module.eks_blueprints
  ]
}

resource "helm_release" "loki" {
  name       = "loki-stack"
  chart      = "loki-stack"
  repository = "https://grafana.github.io/helm-charts"
  namespace  = "loki-stack"

  create_namespace = true

  values = [<<-EOF
    loki:
      persistence:
        enabled: true
        storageClassName: gp2
        accessModes:
          - ReadWriteOnce
        size: 20Gi

    promtail:
      enabled: true
      config:
        clients:
          - url: http://loki-stack:3100/loki/api/v1/push
        positions:
          filename: /var/log/positions.yaml
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
            type: DirectoryOrCreate
      volumeMounts:
        - name: varlog
          mountPath: /var/log
  EOF
  ]

  depends_on = [
    module.eks_blueprints
  ]
}

resource "kubectl_manifest" "grafana_ingress" {
  depends_on = [module.eks_blueprints]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: grafana-ingress
      namespace: kube-prometheus-stack
      annotations:
        nginx.ingress.kubernetes.io/ssl-redirect: "false"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    spec:
      ingressClassName: nginx
      rules:
      - http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
  YAML
}

resource "kubectl_manifest" "prometheus_ingress" {
  depends_on = [module.eks_blueprints]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: prometheus-ingress
      namespace: kube-prometheus-stack
      annotations:
        nginx.ingress.kubernetes.io/ssl-redirect: "false"
        nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
        nginx.ingress.kubernetes.io/rewrite-target: /$2
    spec:
      ingressClassName: nginx
      rules:
      - http:
          paths:
          - path: /prometheus(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-prometheus
                port:
                  number: 9090
  YAML
}

# resource "helm_release" "loki" {
#   name       = "loki"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "loki"
#   namespace  = "default"
#   create_namespace = true

#   values = [
#     file("${path.module}/loki-values.yaml")
#   ]

#   depends_on = [
#     module.eks_blueprints,
#     module.kubernetes_addons
#   ]
# }

# resource "helm_release" "promtail" {
#   name       = "promtail"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "promtail"
#   namespace  = "default"
#   create_namespace = true

#   values = [
#     templatefile("${path.module}/promtail-values.yaml", {
#       cluster_name = module.eks_blueprints.eks_cluster_id
#     })
#   ]

#   depends_on = [
#     helm_release.loki,
#     module.eks_blueprints,
#     module.kubernetes_addons
#   ]
# }