output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "kubeconfig" {
  sensitive = true
  value     = var.enable_legacy_kubeconfig ? local.legacy_kubeconfig : local.gcloud_kubeconfig
}

output "endpoint" {
  value = google_container_cluster.cluster.endpoint
}

output "cluster_ca_certificate" {
  sensitive = true
  value     = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
}

output "client_certificate" {
  sensitive = true
  value     = google_container_cluster.cluster.master_auth[0].client_certificate
}

output "client_key" {
  sensitive = true
  value     = google_container_cluster.cluster.master_auth[0].client_key
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "network_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}

output "k8s_ip_ranges" {
  value = var.k8s_ip_ranges
}

output "instace_urls" {
  value = google_container_cluster.cluster.instance_group_urls
}

output "service_account" {
  value = var.service_account == "" ? element(concat(google_service_account.sa.*.email, [""]), 0) : var.service_account # See here for explanation of ugly syntax: https://www.terraform.io/upgrade-guides/0-11.html#referencing-attributes-from-resources-with-count-0
}

output "service_account_key" {
  value = var.service_account == "" ? element(
    concat(google_service_account_key.sa_key.*.private_key, [""]),
    0,
  ) : "" # See here for explanation of ugly syntax: https://www.terraform.io/upgrade-guides/0-11.html#referencing-attributes-from-resources-with-count-0
}

output "cloud_nat_adddress" {
  value = (var.private_cluster && var.cloud_nat) ? element(concat(google_compute_address.nat.*.address, [""]), 0) : "" # See here for explanation of ugly syntax: https://www.terraform.io/upgrade-guides/0-11.html#referencing-attributes-from-resources-with-count-0
}

# Render Kubeconfig output template
locals {
  legacy_kubeconfig = <<KUBECONFIG

apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://${google_container_cluster.cluster.endpoint}
    certificate-authority-data: ${google_container_cluster.cluster.master_auth[0].cluster_ca_certificate}
  name: gke-${var.name}
users:
- name: gke-${var.name}
  user:
    client-certificate-data: ${google_container_cluster.cluster.master_auth[0].client_certificate}
    client-key-data: ${google_container_cluster.cluster.master_auth[0].client_key}
contexts:
- context:
    cluster: gke-${var.name}
    user: gke-${var.name}
  name: gke-${var.name}
current-context: gke-${var.name}

KUBECONFIG

}

locals {
  gcloud_kubeconfig = <<KUBECONFIG

apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    server: https://${google_container_cluster.cluster.endpoint}
    certificate-authority-data: ${google_container_cluster.cluster.master_auth[0].cluster_ca_certificate}
  name: gke-${var.name}
users:
- name: gke-${var.name}
  user:
    auth-provider:
      config:
        cmd-args: config config-helper --format=json
        cmd-path: "${var.gcloud_path}"
        expiry-key: '{.credential.token_expiry}'
        token-key: '{.credential.access_token}'
      name: gcp
contexts:
- context:
    cluster: gke-${var.name}
    user: gke-${var.name}
  name: gke-${var.name}
current-context: gke-${var.name}

KUBECONFIG

}

