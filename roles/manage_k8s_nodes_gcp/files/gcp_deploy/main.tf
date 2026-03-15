terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
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

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Service account used by all cluster nodes.
# Granted compute.viewer (instance/zone lookups) and compute.loadBalancerAdmin
# (forwarding rules, target pools, health checks, firewall rules) so the
# Cloud Controller Manager can manage GCP load balancers.
resource "google_service_account" "k8s-ccm" {
  account_id   = "${var.gcp_prefix}-ccm"
  display_name = "${var.gcp_prefix} Cloud Controller Manager"
}

resource "google_project_iam_member" "k8s-ccm-viewer" {
  project = var.gcp_project
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.k8s-ccm.email}"
}

resource "google_project_iam_member" "k8s-ccm-lb-admin" {
  project = var.gcp_project
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.k8s-ccm.email}"
}

resource "google_project_iam_member" "k8s-ccm-security-admin" {
  project = var.gcp_project
  role    = "roles/compute.securityAdmin"
  member  = "serviceAccount:${google_service_account.k8s-ccm.email}"
}

# Discover the public IP of the machine running terraform/ansible and restrict admin access to it.
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  ansible_ip = "${chomp(data.http.my_ip.response_body)}/32"
}

resource "google_compute_network" "k8s-vpc" {
  name                    = "${var.gcp_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "k8s-subnet" {
  name          = "${var.gcp_prefix}-subnet"
  network       = google_compute_network.k8s-vpc.id
  ip_cidr_range = var.gcp_subnet_cidr
  region        = var.gcp_region
}

# --- Firewall rules ---
#
# Rule structure mirrors the AWS refactor:
# - east/west: allow all traffic only between cluster nodes (tag-to-tag)
# - admin: SSH + ICMP only from the machine running terraform/ansible
# - apiserver: 6443 only from the machine running terraform/ansible
# - nodeport: optional/demo-friendly access (tunable by gcp_nodeport_cidr)

# 1) Allow all traffic between cluster nodes (east-west) by tag.
resource "google_compute_firewall" "k8s-internal" {
  name    = "${var.gcp_prefix}-internal"
  network = google_compute_network.k8s-vpc.name

  direction = "INGRESS"
  priority  = 1000

  source_tags = ["k8s-role"]
  target_tags = ["k8s-role"]

  allow {
    protocol = "all"
  }
}

# 2) Admin access from the Ansible control machine (SSH + ICMP).
resource "google_compute_firewall" "k8s-admin" {
  name    = "${var.gcp_prefix}-admin"
  network = google_compute_network.k8s-vpc.name

  direction = "INGRESS"
  priority  = 900

  source_ranges = [local.ansible_ip]
  target_tags   = ["k8s-role"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# 3) Kubernetes API server access from the Ansible control machine.
resource "google_compute_firewall" "k8s-apiserver" {
  name    = "${var.gcp_prefix}-apiserver"
  network = google_compute_network.k8s-vpc.name

  direction = "INGRESS"
  priority  = 910

  source_ranges = [local.ansible_ip]
  target_tags   = ["master"]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# 4) NodePort access (demo-friendly). Tighten gcp_nodeport_cidr for safer demos/production.
resource "google_compute_firewall" "k8s-nodeport" {
  name    = "${var.gcp_prefix}-nodeport"
  network = google_compute_network.k8s-vpc.name

  direction = "INGRESS"
  priority  = 920

  source_ranges = [var.gcp_nodeport_cidr]
  target_tags   = ["node", "master"]

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
}

# 5) Allow GCP health check probes (35.191.0.0/16, 130.211.0.0/22) to reach
#    all cluster nodes on any TCP port (covers NodePort health checks).
resource "google_compute_firewall" "k8s-gcp-healthcheck" {
  name    = "${var.gcp_prefix}-gcp-healthcheck"
  network = google_compute_network.k8s-vpc.name

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["k8s-role"]

  allow {
    protocol = "tcp"
  }
}

resource "tls_private_key" "k8s-tls-private-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "google_compute_instance" "k8s-worker-nodes" {
  count        = var.num_instances
  name         = "${var.gcp_prefix}-worker-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.gcp_zone
  tags         = ["k8s-role", "node"]

  boot_disk {
    device_name = "${var.gcp_prefix}-worker-disk-${count.index + 1}"
    auto_delete = true

    initialize_params {
      size  = var.cloud_worker_volume_size
      image = var.gcp_disk_image
    }
  }

  metadata = {
    ssh-keys = "${var.gcp_instance_username}:${tls_private_key.k8s-tls-private-key.public_key_openssh}"
  }

  labels = {
    cluster-name   = var.gcp_prefix
    application    = "kubeadm-k8s"
    role           = "node"
    cloud_provider = "gcp"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s-subnet.name
    access_config {}
  }

  service_account {
    email  = google_service_account.k8s-ccm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_compute_instance" "k8s-master-nodes" {
  count        = 1
  name         = "${var.gcp_prefix}-master-${count.index + 1}"
  machine_type = var.master_machine_type
  zone         = var.gcp_zone
  tags         = ["k8s-role", "master"]

  boot_disk {
    device_name = "${var.gcp_prefix}-master-disk-${count.index + 1}"
    auto_delete = true

    initialize_params {
      size  = var.cloud_master_volume_size
      image = var.gcp_disk_image
    }
  }

  metadata = {
    ssh-keys = "${var.gcp_instance_username}:${tls_private_key.k8s-tls-private-key.public_key_openssh}"
  }

  labels = {
    cluster-name   = var.gcp_prefix
    application    = "kubeadm-k8s"
    role           = "master"
    cloud_provider = "gcp"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s-subnet.name
    access_config {}
  }

  service_account {
    email  = google_service_account.k8s-ccm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "local_file" "k8s-local-private-key" {
  content         = tls_private_key.k8s-tls-private-key.private_key_pem
  filename        = "/tmp/${var.gcp_prefix}-key-private.pem"
  file_permission = "0600"
}

resource "local_file" "k8s-local-public-key" {
  content         = tls_private_key.k8s-tls-private-key.public_key_openssh
  filename        = "/tmp/${var.gcp_prefix}-key.pub"
  file_permission = "0600"
}
