# Required
##########################################################
variable "name" {
  description = "Name to use as a prefix to all the resources."
}

variable "region" {
  description = "The region to create the cluster in (automatically distributes masters and nodes across zones). See: https://cloud.google.com/kubernetes-engine/docs/concepts/regional-clusters"
}

# Optional
##########################################################
variable "project" {
  description = "The ID of the google project to which the resource belongs."
  default     = ""
}

variable "description" {
  default = "Managed by Terraform"
}

variable "enable_legacy_kubeconfig" {
  description = "Whether to enable authentication using tokens/passwords/certificates. If disabled, the gcloud client needs to be used to authenticate to k8s."
  default     = false
}

variable "k8s_version" {
  description = "Default K8s version for the Control Plane. See: https://www.terraform.io/docs/providers/google/r/container_cluster.html#min_master_version"
  default     = "1.12"
}

variable "node_version" {
  description = "K8s version for Nodes. If no value is provided, this defaults to the value of k8s_version."
  default     = ""
}

variable "private_cluster" {
  description = "If true, a private cluster will be created, meaning nodes do not get public IP addresses. It is mandatory to specify master_ipv4_cidr_block and ip_allocation_policy with this option."
  default     = false
}

variable "gcloud_path" {
  description = "The path to your gcloud client binary."
  default     = "gcloud"
}

variable "service_account" {
  description = "The service account to be used by the Node VMs. If not specified, a service account will be created with minimum permissions."
  default     = ""
}

variable "remove_default_node_pool" {
  description = "Whether to delete the default node pool on creation. Defaults to true"
  default     = true
}

variable "cloud_nat" {
  description = "Whether or not to enable Cloud NAT. This is to retain compatability with clusters that use the old NAT Gateway module."
  default     = true
}

variable "nat_bgp_asn" {
  description = "Local BGP Autonomous System Number (ASN). Must be an RFC6996 private ASN, either 16-bit or 32-bit. The value will be fixed for this router resource. All VPN tunnels that link to this router will have the same local ASN."
  default     = "64514"
}
