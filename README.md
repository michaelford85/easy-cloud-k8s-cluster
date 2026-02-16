# easy-kubeadm-k8s-cluster

Provision a Kubernetes cluster on AWS or GCP using **Terraform** for infrastructure
and **Ansible + kubeadm** for cluster bootstrap.

This project automates:

- Cloud infrastructure provisioning (VPC, subnets, security groups/firewalls, instances)
- Kubernetes installation via kubeadm
- Container runtime configuration (containerd)
- Cluster bootstrap and kubeconfig retrieval
- Optional teardown of all infrastructure

---

## Why This Project Exists

This repository provides a simple, reproducible way to stand up a real
kubeadm-based Kubernetes cluster in the cloud without relying on managed
Kubernetes services.

It is ideal for:

- Learning kubeadm internals
- Demonstrations and workshops
- CI experimentation
- Infrastructure automation examples
- Extending into larger demo environments

---

## Architecture Overview

- **Terraform** provisions infrastructure (AWS or GCP)
- **Ansible** configures instances
- **kubeadm** initializes the control plane and joins workers
- **containerd** is used as the container runtime
- kubeconfig is exported locally for cluster access

---

# Prerequisites

Install locally:

- Python 3.9+
- Ansible
- Terraform >= 1.5
- kubectl
- Cloud CLI (aws or gcloud)
- Cloud credentials configured

---

# Installation

Clone the repository:

```bash
git clone https://github.com/michaelford85/easy-kubeadm-k8s-cluster.git
cd easy-kubeadm-k8s-cluster
```

Install Ansible dependencies:

```bash
ansible-galaxy install -r requirements.yml
pip install -r requirements.txt
```

Example `requirements.yml`:
https://gist.github.com/michaelford85/REPLACE_WITH_REQUIREMENTS_GIST

---

# Configuration

Edit:

```
vars/default-vars.yml
```

Key variables (updated for current refactor):

```yaml
cloud_provider: aws_ec2  # or gcp
cloud_prefix: kubeadm-cluster

# Kubernetes
num_instances: 2

# AWS
ec2_region: us-east-2
ec2_vpc_cidr: "192.168.0.0/16"
ec2_vpc_subnet: "192.168.0.0/20"
aws_instance_username: ubuntu

# GCP
gcp_project: your-project-id
gcp_region: us-central1
gcp_zone: us-central1-a
gcp_disk_image: projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts
gcp_instance_username: ubuntu
```

Full example:
https://gist.github.com/michaelford85/REPLACE_WITH_DEFAULT_VARS_GIST

---

# Provision Infrastructure

Run:

```bash
ansible-playbook provision-kubeadm-cluster.yml
```

AWS provisioning example:
https://gist.github.com/michaelford85/REPLACE_WITH_AWS_PROVISION_GIST

GCP provisioning example:
https://gist.github.com/michaelford85/REPLACE_WITH_GCP_PROVISION_GIST

---

# Bootstrap Kubernetes

After infrastructure is provisioned:

```bash
ansible-playbook bootstrap-kubeadm-cluster.yml
```

Bootstrap example:
https://gist.github.com/michaelford85/REPLACE_WITH_BOOTSTRAP_GIST

When complete, export kubeconfig:

```bash
export KUBECONFIG=/tmp/kubeadm-cluster-config
kubectl get nodes
```

---

# Deploy a Test Application

Example NGINX deployment (3 replicas):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

Apply:

```bash
kubectl apply -f nginx.yaml
kubectl get pods -o wide
```

Example test manifest gist:
https://gist.github.com/michaelford85/REPLACE_WITH_NGINX_GIST

---

# Teardown

Destroy infrastructure:

```bash
ansible-playbook teardown-kubeadm-cluster.yml
```

Teardown example:
https://gist.github.com/michaelford85/REPLACE_WITH_TEARDOWN_GIST

---

# Notes & Best Practices

- SSH access is restricted to the control machine public IP.
- containerd is configured with systemd cgroup driver.
- sysctl `net.ipv4.ip_forward` is enabled automatically.
- Use image families (e.g., ubuntu-2204-lts) instead of pinned image versions.
- Use dedicated IAM roles / service accounts with least privilege.
- Avoid `--ignore-preflight-errors` in production environments.

---

# Project Structure

```
roles/
  manage_k8s_nodes_aws/
  manage_k8s_nodes_gcp/
vars/
  default-vars.yml
terraform/
  aws_deploy/
  gcp_deploy/
```

---

# License

MIT
