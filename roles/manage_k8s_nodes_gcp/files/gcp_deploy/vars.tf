variable "num_instances" {
  description = "The number of instances to deploy in the public cloud"
  type        = number
  default     = 1
}

variable "gcp_disk_image" {
  description = "The image to use for the GCP compute instances (e.g., ubuntu-2204-lts)"
  type        = string
  default     = "xxxx"
}

variable "gcp_region" {
  description = "The GCP region to operate in"
  type        = string
  default     = "pppp"
}

variable "gcp_zone" {
  description = "The GCP zone to operate in"
  type        = string
  default     = "zzzz"
}

variable "gcp_prefix" {
  description = "The prefix to place in front of all GCP resources"
  type        = string
  default     = "ffff"
}

variable "machine_type" {
  description = "The machine type to use for the Kubernetes worker nodes"
  type        = string
  default     = "xxxx"
}

variable "master_machine_type" {
  description = "The machine type to use for the Kubernetes control-plane node"
  type        = string
  default     = "e2-standard-4"
}

variable "gcp_instance_username" {
  description = "Username to embed in instance SSH metadata (Ubuntu images typically use 'ubuntu')"
  type        = string
  default     = "ubuntu"
}

variable "gcp_key" {
  description = "Path to the GCP service-account JSON key file used to authenticate with GCP"
  type        = string
  default     = "mmmm"
}

variable "gcp_project" {
  description = "The name of the GCP project that this script will operate on"
  type        = string
  default     = "nnnn"
}

variable "gcp_vpc_cidr" {
  description = "CIDR block for the Kubernetes VPC network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "gcp_subnet_cidr" {
  description = "CIDR block for the Kubernetes subnetwork (must be contained within gcp_vpc_cidr)"
  type        = string
  default     = "192.168.0.0/20"
}

variable "gcp_nodeport_cidr" {
  description = "CIDR allowed to access NodePort services (demo default 0.0.0.0/0; tighten to your /32 for safety)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "cloud_master_volume_size" {
  description = "The boot disk size (GB) for k8s masters"
  type        = number
  default     = 10
}

variable "cloud_worker_volume_size" {
  description = "The boot disk size (GB) for k8s workers"
  type        = number
  default     = 10
}
