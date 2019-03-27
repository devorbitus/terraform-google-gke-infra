# Need to use Beta provider for private_cluster feature
##########################################################
#provider "google-beta" {
#  version = "~> 1.19"
#  region  = "${var.region}"
#}

# GKE
##########################################################
resource "google_container_cluster" "cluster" {
  provider                          = "google-beta"
  name                              = "${var.name}"
  project                           = "${var.project}"
  region                            = "${var.region}"
  network                           = "${google_compute_network.vpc.name}"            # https://github.com/terraform-providers/terraform-provider-google/issues/1792
  subnetwork                        = "${google_compute_subnetwork.subnet.self_link}"
  cluster_ipv4_cidr                 = "${var.k8s_ip_ranges["pod_cidr"]}"
  description                       = "${var.description}"
  enable_binary_authorization       = "${var.k8s_options["binary_authorization"]}"
  enable_kubernetes_alpha           = "${var.extras["kubernetes_alpha"]}"
  enable_legacy_abac                = "${var.enable_legacy_kubeconfig}"
  logging_service                   = "${var.k8s_options["logging_service"]}"
  master_authorized_networks_config = "${var.networks_that_can_access_k8s_api}"
  master_ipv4_cidr_block            = "${var.k8s_ip_ranges["master_cidr"]}"
  min_master_version                = "${var.k8s_version}"
  monitoring_service                = "${var.k8s_options["monitoring_service"]}"
  node_version                      = "${var.node_version}"
  private_cluster                   = "${var.private_cluster}"
  remove_default_node_pool          = "${var.remove_default_node_pool}"

  # resource_labels = []
  addons_config {
    horizontal_pod_autoscaling {
      disabled = "${var.k8s_options["enable_hpa"] == 1 ? false : true}" # enabled: y/n
    }

    http_load_balancing {
      disabled = "${var.k8s_options["enable_http_load_balancing"] == 1 ? false : true}" # enabled: y/n
    }

    kubernetes_dashboard {
      disabled = "${var.k8s_options["enable_dashboard"] == 1 ? false : true}" # enabled: y/n
    }

    network_policy_config {
      disabled = "${var.k8s_options["enable_network_policy"] == 1 ? false : true}" # enabled: y/n
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.name}-k8s-pod"
    services_secondary_range_name = "${var.name}-k8s-svc"
  }

  lifecycle {
    ignore_changes = ["node_count"]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "${var.extras["maintenance_start_time"]}"
    }
  }

  master_auth {
    username                  = ""                                 # Disable basic auth
    password                  = ""                                 # Disable basic auth
    client_certificate_config = "${var.client_certificate_config}"
  }

  network_policy {
    enabled  = "${var.k8s_options["enable_network_policy"]}"
    provider = "${var.k8s_options["enable_network_policy"] == 1 ? "CALICO" : "PROVIDER_UNSPECIFIED" }"
  }

  node_pool {
    name = "default-pool"
  }

  pod_security_policy_config {
    enabled = "${var.k8s_options["enable_pod_security_policy"]}"
  }

  # TODO: this config causes a permadiff if private_cluster is set to false
  # Need to revisit once terraform v0.12 comes out or if there's changes to the GCP API
  # private_cluster_config {
  #   enable_private_nodes   = "${var.private_cluster}"
  #   master_ipv4_cidr_block = "${var.k8s_ip_ranges["master_cidr"]}"
  # }
  timeouts {
    create = "${var.timeouts["create"]}"
    update = "${var.timeouts["update"]}"
    delete = "${var.timeouts["delete"]}"
  }
}

resource "google_container_node_pool" "primary_pool" {
  name               = "${var.name}-primary-pool"
  cluster            = "${google_container_cluster.cluster.name}"
  region             = "${var.region}"
  initial_node_count = "${var.node_pool_options["autoscaling_nodes_min"]}"

  autoscaling {
    min_node_count = "${var.node_pool_options["autoscaling_nodes_min"]}"
    max_node_count = "${var.node_pool_options["autoscaling_nodes_max"]}"
  }

  management {
    auto_repair  = "${var.node_pool_options["auto_repair"]}"
    auto_upgrade = "${var.node_pool_options["auto_upgrade"]}"
  }

  max_pods_per_node = "${var.node_pool_options["max_pods_per_node"]}"

  node_config {
    disk_size_gb = "${var.node_options["disk_size"]}"
    disk_type    = "${var.node_options["disk_type"]}"

    # Forces new resource due to computing count :/
    # guest_accelerator {
    #   count = "${length(var.node_options["guest_accelerator"])}"
    #   type = "${var.node_options["guest_accelerator"]}"
    # }
    image_type = "${var.node_options["image"]}"

    # labels = "${var.node_labels}" # Forces new resource due to computing count :/
    local_ssd_count = "${var.extras["local_ssd_count"]}"
    machine_type    = "${var.node_options["machine_type"]}"
    metadata        = "${var.node_metadata}"

    # minimum_cpu_platform = "" # TODO
    oauth_scopes    = "${var.oauth_scopes}"
    preemptible     = "${var.node_options["preemptible"]}"
    service_account = "${var.service_account == "" ? element(concat(google_service_account.sa.*.email, list("")),0) : var.service_account }" # See here for explanation of ugly syntax: https://www.terraform.io/upgrade-guides/0-11.html#referencing-attributes-from-resources-with-count-0
    tags            = "${split(",", length(var.node_tags) == 0 ? var.name : join(",", var.node_tags))}"

    # TODO
    # taint {
    #   key = ""
    #   value = ""
    #   effect = ""
    # }
    workload_metadata_config = {
      node_metadata = "${var.extras["metadata_config"]}"
    }
  }
}
