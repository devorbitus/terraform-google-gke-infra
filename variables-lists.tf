# List: Networks that are authorized to access the K8s API
###############################
variable "networks_that_can_access_k8s_api" {
  type        = "list"
  description = "A list of networks that can access the K8s API. By default allows Montreal, Munich, Gliwice offices as well as Concourse and a few VPN networks."

  default = [{
    cidr_blocks = [{}]
  }]
}

# List: Minimum GCP API privileges to allow to the nodes
###############################
variable "oauth_scopes" {
  type        = "list"
  description = "The set of Google API scopes to be made available on all of the node VMs under the default service account. See: https://www.terraform.io/docs/providers/google/r/container_cluster.html#oauth_scopes"

  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/compute",
  ]
}

# List: Minimum roles to grant to the default Node Service Account
###############################
variable "service_account_iam_roles" {
  type        = "list"
  description = "A list of roles to apply to the service account if one is not provided. See: https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#use_least_privilege_sa"

  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/storage.objectViewer",
  ]
}

# List: Tags to apply to the nodes
###############################
variable "node_tags" {
  type        = "list"
  default     = []
  description = "The list of instance tags applied to all nodes. Tags are used to identify valid sources or targets for network firewalls. If none are provided, the cluster name is used as default."
}

# List: Whether to enable client certificate authorization
###############################
# The format to use is:
#
# client_certificate_config = [{
#   issue_client_certificate = true
# }]
variable "client_certificate_config" {
  description = "Whether client certificate authorization is enabled for this cluster."
  default     = []
}

# variable "node_labels" {
#   type        = "list"
#   default     = []
#   description = "The Kubernetes labels (key/value pairs) to be applied to each node."
# }


# variable "node_taints" {
#   type        = "list"
#   default     = []
#   description = "List of kubernetes taints to apply to each node."
# }

