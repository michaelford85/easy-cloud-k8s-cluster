terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}

provider "aws" {
  region                   = var.ec2_region
  shared_credentials_files = [var.aws_key]
  profile                  = var.aws_profile
}

# Discover the public IP of the machine running terraform/ansible and restrict admin access to it.
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  ansible_ip = "${chomp(data.http.my_ip.response_body)}/32"
}

resource "aws_vpc" "k8s-vpc" {
  cidr_block           = var.ec2_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    application                              = "kubeadm-k8s"
    cluster-name                             = var.ec2_prefix
    Name                                     = "${var.ec2_prefix}-vpc"
    "kubernetes.io/cluster/${var.ec2_prefix}" = "owned"
  }
}

resource "aws_security_group" "k8s-master-sg" {
  name   = "${var.ec2_prefix}-master-sg"
  vpc_id = aws_vpc.k8s-vpc.id

  # Admin access (only from Ansible control machine)
  ingress {
    description = "SSH from Ansible control machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.ansible_ip]
  }

  ingress {
    description = "ICMP from Ansible control machine"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.ansible_ip]
  }

  # Kubernetes API access:
  # - from Ansible control machine for kubeadm/kubectl during bootstrap
  ingress {
    description = "kube-apiserver from Ansible control machine"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [local.ansible_ip]
  }

  # Control-plane internal ports (keep tight)
  ingress {
    description = "etcd (self only)"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kubelet on master (self only)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kube-scheduler (self only)"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "kube-controller-manager (self only)"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    self        = true
  }

  # Allow all traffic within the master SG (covers loopback + any future multi-master expansion if you later
  # attach additional control-plane nodes to this SG).
  ingress {
    description = "Allow all internal traffic within master SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Egress should be open so nodes can reach package repos, container registries, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    application  = "kubeadm-k8s"
    cluster-name = var.ec2_prefix
    Name         = "${var.ec2_prefix}-master-sg"
  }
}

resource "aws_security_group" "k8s-worker-sg" {
  name   = "${var.ec2_prefix}-worker-sg"
  vpc_id = aws_vpc.k8s-vpc.id

  # Admin access (only from Ansible control machine)
  ingress {
    description = "SSH from Ansible control machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.ansible_ip]
  }

  ingress {
    description = "ICMP from Ansible control machine"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.ansible_ip]
  }

  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort Services (lab-friendly). Tighten to [local.ansible_ip] if you want it private.
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic within the worker SG (covers worker-to-worker)
  ingress {
    description = "Allow all internal traffic within worker SG"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Egress should be open so nodes can reach package repos, container registries, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    application                              = "kubeadm-k8s"
    cluster-name                             = var.ec2_prefix
    Name                                     = "${var.ec2_prefix}-worker-sg"
    "kubernetes.io/cluster/${var.ec2_prefix}" = "owned"
  }
}

# --- Cross-SG cluster rules (defined as separate resources to avoid Terraform dependency cycles) ---

# Workers -> API server on master
resource "aws_security_group_rule" "master_api_from_workers" {
  type                     = "ingress"
  description              = "kube-apiserver from workers"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s-master-sg.id
  source_security_group_id = aws_security_group.k8s-worker-sg.id
}

# Master -> kubelet on workers
resource "aws_security_group_rule" "worker_kubelet_from_master" {
  type                     = "ingress"
  description              = "kubelet from control plane"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s-worker-sg.id
  source_security_group_id = aws_security_group.k8s-master-sg.id
}

# Allow all traffic master <-> workers for cluster networking (Calico, overlays, node-to-node, etc.)
resource "aws_security_group_rule" "master_all_from_workers" {
  type                     = "ingress"
  description              = "Allow all internal cluster traffic from workers to master"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s-master-sg.id
  source_security_group_id = aws_security_group.k8s-worker-sg.id
}

resource "aws_security_group_rule" "workers_all_from_master" {
  type                     = "ingress"
  description              = "Allow all internal cluster traffic from master to workers"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s-worker-sg.id
  source_security_group_id = aws_security_group.k8s-master-sg.id
}

resource "aws_subnet" "k8s-subnet" {
  vpc_id                  = aws_vpc.k8s-vpc.id
  cidr_block              = var.ec2_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    cluster-name                             = var.ec2_prefix
    application                              = "kubeadm-k8s"
    Name                                     = "${var.ec2_prefix}-subnet"
    "kubernetes.io/cluster/${var.ec2_prefix}" = "owned"
    "kubernetes.io/role/elb"                 = "1"
  }
}

resource "aws_internet_gateway" "k8s-igw" {
  vpc_id = aws_vpc.k8s-vpc.id

  tags = {
    cluster-name = var.ec2_prefix
    application  = "kubeadm-k8s"
    Name         = "${var.ec2_prefix}-igw"
  }
}

resource "aws_default_route_table" "k8s-route-table" {
  default_route_table_id = aws_vpc.k8s-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s-igw.id
  }

  tags = {
    cluster-name = var.ec2_prefix
    application  = "kubeadm-k8s"
    Name         = "${var.ec2_prefix}-route-table"
  }
}

resource "tls_private_key" "k8s-tls-private-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s-key" {
  key_name   = "${var.ec2_prefix}-key"
  public_key = tls_private_key.k8s-tls-private-key.public_key_openssh
}

resource "aws_instance" "k8s-worker-nodes" {
  count         = var.num_instances
  ami           = var.ec2_image_id
  instance_type = var.machine_type
  key_name      = aws_key_pair.k8s-key.key_name
  subnet_id     = aws_subnet.k8s-subnet.id

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.cloud_worker_volume_size
  }

  vpc_security_group_ids = [aws_security_group.k8s-worker-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s-ccm-instance-profile.name

  tags = {
    Name                                     = "${var.ec2_prefix}-worker-${count.index + 1}"
    cluster-name                             = var.ec2_prefix
    application                              = "kubeadm-k8s"
    cloud_provider                           = "aws"
    role                                     = "node"
    "kubernetes.io/cluster/${var.ec2_prefix}" = "owned"
  }
}

resource "aws_instance" "k8s-master-node" {
  count         = 1
  ami           = var.ec2_image_id
  instance_type = var.master_machine_type
  key_name      = aws_key_pair.k8s-key.key_name
  subnet_id     = aws_subnet.k8s-subnet.id

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.cloud_master_volume_size
  }

  vpc_security_group_ids = [aws_security_group.k8s-master-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s-ccm-instance-profile.name

  tags = {
    Name                                     = "${var.ec2_prefix}-master"
    cluster-name                             = var.ec2_prefix
    application                              = "kubeadm-k8s"
    cloud_provider                           = "aws"
    role                                     = "master"
    "kubernetes.io/cluster/${var.ec2_prefix}" = "owned"
  }
}

resource "local_file" "k8s-local-private-key" {
  content         = tls_private_key.k8s-tls-private-key.private_key_pem
  filename        = "/tmp/${var.ec2_prefix}-key-private.pem"
  file_permission = "0600"
}

resource "local_file" "k8s-local-public-key" {
  content         = tls_private_key.k8s-tls-private-key.public_key_openssh
  filename        = "/tmp/${var.ec2_prefix}-key.pub"
  file_permission = "0600"
}

# --- IAM for Cloud Controller Manager ---
# Grants EC2 instances the permissions the AWS CCM needs to manage
# load balancers, security group rules, and node lifecycle.

data "aws_iam_policy_document" "k8s-ccm-assume-role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "k8s-ccm-role" {
  name               = "${var.ec2_prefix}-ccm-role"
  assume_role_policy = data.aws_iam_policy_document.k8s-ccm-assume-role.json

  tags = {
    application  = "kubeadm-k8s"
    cluster-name = var.ec2_prefix
  }
}

resource "aws_iam_policy" "k8s-ccm-policy" {
  name        = "${var.ec2_prefix}-ccm-policy"
  description = "IAM policy for the Kubernetes AWS Cloud Controller Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTopology",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcs",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
          "iam:CreateServiceLinkedRole",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "k8s-ccm-policy-attach" {
  role       = aws_iam_role.k8s-ccm-role.name
  policy_arn = aws_iam_policy.k8s-ccm-policy.arn
}

resource "aws_iam_instance_profile" "k8s-ccm-instance-profile" {
  name = "${var.ec2_prefix}-ccm-instance-profile"
  role = aws_iam_role.k8s-ccm-role.name
}
