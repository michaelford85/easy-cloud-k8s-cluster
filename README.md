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

```
---
roles:
  - name: geerlingguy.docker
    version: 8.0.0
  - name: geerlingguy.pip
    version: 3.1.2
  - name: geerlingguy.kubernetes
    version: 8.2.0
  - name: geerlingguy.containerd
    version: 1.4.1

collections:
  - name: amazon.aws
    version: 11.1.0
  - name: community.aws
    version: 11.0.0
  - name: google.cloud
    version: 1.11.0
  - name: community.general
    version: 12.3.0
  - name: kubernetes.core
    version: 6.3.0
  - name: ansible.posix
    version: 2.1.0
```

---

# Configuration

`vars/default-vars.yml` is an example variable file. Copy it to `vars/custom-vars.yml` and edit that file:

```bash
cp vars/default-vars.yml vars/custom-vars.yml
```

The playbooks will automatically use `vars/custom-vars.yml` if it exists, otherwise they fall back to `vars/default-vars.yml`.

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
```
---
# This value specifies a location where all artifacts (SSH key pairs, kubeconfig, 
# terraform state) will be placed when creating your Kubernetes cluster.
working_dir: /tmp

# This value specifies which public cloud provider to deploy resources to.
# acceptable options: aws_ec2, gcp
cloud_provider: aws_ec2

# This value will be added to the names of all provisioned cloud resources
# (instances, firewalls, security groups, etc.)
cloud_prefix: kubeadm-cluster

# This value specifies the number of kubernetes WORKER nodes;
# set to 0 and set kubernetes_allow_pods_on_master to "yes"
# if you desire a single node k8s cluster
num_instances: 4

# This value determines whether or not you allow PODs on the master node.
# If you’d like to create a single node cluster (very helpful 
# for saving on cloud costs), set this value to yes and set num_instances to 0.
kubernetes_allow_pods_on_master: no


# This value determines what cloud instance type will be used for the worker nodes.
# Valid values (and the resulting instance types) are:
#    large:
#        AWS: t3.large
#        GCP: e2-standard-2
#    xlarge:
#        AWS: t3.xlarge
#        GCP: e2-standard-4
# instance_size: xlarge
instance_size: large

# This value determines the disk size (in GB) of the master node
cloud_master_volume_size: 50

# This value determines the disk size (in GB) of the worker node(s)
cloud_worker_volume_size: 100

##### Global kubernetes settings; regardless of cloud provider #####

# This value determines which version of Kubernetes to provision, in 1.XX format
# A list of all releases can be found here:
# https://kubernetes.io/releases/
kubernetes_version: '1.34'
kubernetes_version_kubeadm: "v{{ kubernetes_version }}.0"

# Path to the kubeadm-generated kubelet configuration file.
# This file is created during `kubeadm init` or `kubeadm join` and defines
# kubelet runtime configuration such as cgroup driver, cluster DNS, etc.
kubernetes_kubeadm_kubelet_config_file_path: '/etc/kubernetes/kubeadm-kubelet-config.yaml'

kubernetes_pod_network:
  cni: "calico"
  cidr: '10.0.40.0/24'

#Calico manifest - grab the latest version of the manifest from:
kubernetes_calico_manifest_file: "https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/calico.yaml"

# Additional arguments passed to the `kubeadm join` command.
# Historically used to suppress specific preflight errors (e.g., Port-10250 in use).
# NOT recommended for production use — ignoring preflight errors can hide
# real configuration issues such as stale kubelet state or misconfigured sysctl values.
kubernetes_join_command_extra_opts: "--ignore-preflight-errors=Port-10250"

# Global kubeadm preflight error suppression.
# When set to "all", kubeadm will ignore ALL safety checks before initialization/join.
# Strongly discouraged outside of debugging scenarios. Leaving this enabled
# may allow a cluster to initialize in a broken or insecure state.
kubernetes_ignore_preflight_errors: "all"

##### AWS-specific parameters #####

# If you choose to deploy your cluster to AWS, this variable tells the provisioner
# where to look for your local AWS Programmatic credentials. If you already have
# aws-cli installed (not required), these are typically at $HOME/.aws/credentials,
# but you can specify elsewhere. In order to avoid any confusion, use the absolute path.
aws_local_credentials_file: "~/.aws/credentials"

# This value specifies the AWS credentials file profile (for if you have more than one set 
# of AWS programmatic credentials in your credentials file)
aws_credential_profile: "default"

# This value determines what AWS region to provision resources to.
ec2_region: us-east-2

# Hard coded Amazon Machine Image for Ubuntu 22.04 in us-east-2 region
ec2_image_id: ami-0503ed50b531cc445


# Whether Terraform should wait for EC2 instances to fully initialize
# before continuing execution. Recommended to keep enabled to avoid
# SSH timing issues during Ansible provisioning.
ec2_wait: yes

# Subnet CIDR block for the Kubernetes cluster within the VPC.
# Worker and control-plane nodes will be provisioned inside this subnet.
# Must be contained within ec2_vpc_cidr.
ec2_vpc_subnet: "192.168.0.0/20"

# CIDR block for the entire AWS VPC created for the cluster.
# All cluster networking (nodes + pod overlay traffic) lives within this range.
# Ensure this does NOT overlap with your local network or other VPCs.
ec2_vpc_cidr: "192.168.0.0/16"

# Default SSH username for AWS Ubuntu AMIs.
# This must match the base image being used (Ubuntu = ubuntu, Amazon Linux = ec2-user).
aws_instance_username: ubuntu
```

---

# Provision Infrastructure

Run:

```bash
ansible-playbook provision-kubeadm-cluster.yml
```
## Confirm Cloud Inventory

You can confirm the existence of these instances without even having to log into your cloud provider’s web console, by running the `ansible-inventory` command, and specifying the appropriate dynamic inventory source (found in the repository):

AWS: `./k8s.aws_ec2.yml`
GCP: `./k8s.gcp.yml`

An example of the command and output is here:
```
(ansible) ford@infra01:~/git-workspace/easy-cloud-k8s-cluster$ ansible-inventory -i k8s.aws_ec2.yml --graph
@all:
  |--@ungrouped:
  |--@aws_ec2:
  |  |--kubeadm-cluster-master
  |  |--kubeadm-cluster-worker-1
  |  |--kubeadm-cluster-worker-4
  |  |--kubeadm-cluster-worker-3
  |  |--kubeadm-cluster-worker-2
  |--@k8s_master:
  |  |--kubeadm-cluster-master
  |--@k8s_node:
  |  |--kubeadm-cluster-worker-1
  |  |--kubeadm-cluster-worker-4
  |  |--kubeadm-cluster-worker-3
  |  |--kubeadm-cluster-worker-2
```

---

# Bootstrap Kubernetes

Now that the instances are provisioned, you can install Kubernetes. The `bootstrap-kubeadm-cluster.yml` playbook will:

- Install the pip3 package management system on all nodes
- Install the containerd container runtime on all nodes
- Install the appropriate Kubernetes components on all nodes
- Copy the kubeconfig file from the master node to your local workstation

Again, specify the appropriate dynamic inventory script based on the cloud provider you are using. This is the command based in the AWS-based cluster in this tutorial:

`$ ansible-playbook bootstrap-kubeadm-cluster.yml -i k8s.aws_ec2.yml`

The bootstrap process will take 2-4 minutes to complete.

# Set the KUBECONFIG environment variable

In order to access your Kubernetes cluster via the command line, you can set the `KUBECONFIG` environment variable to point to your newly created `/{{ working_dir }}/{{ cloud_prefix }}-config`. Using the values from our example `custom-vars.yml` file:

`$ export KUBECONFIG=/tmp/kubeadm-cluster-config`

Now you can confirm both ready status of and authentication to the cluster using `kubectl`:

```
(ansible) ford@infra01:~/git-workspace/easy-cloud-k8s-cluster$ kubectl get node
NAME                STATUS   ROLES           AGE     VERSION
ip-192-168-13-127   Ready    control-plane   2m34s   v1.34.5
ip-192-168-3-131    Ready    <none>          2m22s   v1.34.5
ip-192-168-5-146    Ready    <none>          2m22s   v1.34.5
ip-192-168-5-59     Ready    <none>          2m22s   v1.34.5
ip-192-168-7-35     Ready    <none>          2m22s   v1.34.5
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
