# Need to use Beta provider for private_cluster feature
##########################################################

# GKE
##########################################################

data "google_project" "shared_vpc_project" {
  count      = (var.shared_vpc_project_name != "") ? 1 : 0
  project_id = var.shared_vpc_project_name
}

data "google_project" "current_project" {
}

resource "google_compute_shared_vpc_service_project" "spinnaker" {
  count           = (var.shared_vpc_name != "") ? 1 : 0
  host_project    = var.shared_vpc_project_name
  service_project = data.google_project.current_project.project_id
}

data "google_compute_network" "shared-network" {
  count   = (var.shared_vpc_name != "") ? 1 : 0
  name    = var.shared_vpc_name
  project = var.shared_vpc_project_name
}

resource "google_project_iam_member" "container_engine_robot" {
  count   = (var.shared_vpc_project_name != "") ? 1 : 0
  project = var.shared_vpc_project_name
  role    = "roles/compute.networkUser"
  member  = join("", ["serviceAccount:service-", data.google_project.current_project.number, "@container-engine-robot.iam.gserviceaccount.com"])
}

resource "google_project_iam_member" "cloud_services_account" {
  count   = (var.shared_vpc_project_name != "") ? 1 : 0
  project = var.shared_vpc_project_name
  role    = "roles/compute.networkUser"
  member  = join("", ["serviceAccount:", data.google_project.current_project.number, "@cloudservices.gserviceaccount.com"])
}

resource "google_project_iam_binding" "host_service_agent_iam" {
  count   = (var.shared_vpc_project_name != "") ? 1 : 0
  project = var.shared_vpc_project_name
  role    = "roles/container.hostServiceAgentUser"

  members = [
    join("", ["serviceAccount:service-", data.google_project.current_project.number, "@container-engine-robot.iam.gserviceaccount.com"]),
  ]
}

locals {
  private_cluster = var.private_cluster ? ["private"] : []
}

resource "google_container_cluster" "cluster" {
  provider                    = google-beta
  name                        = var.name
  project                     = var.project
  region                      = var.region
  network                     = (var.shared_vpc_name != "") ? data.google_compute_network.shared-network[0].self_link : google_compute_network.vpc[0].self_link # https://github.com/terraform-providers/terraform-provider-google/issues/1792
  subnetwork                  = google_compute_subnetwork.subnet.self_link
  cluster_ipv4_cidr           = var.k8s_ip_ranges["pod_cidr"]
  description                 = var.description
  enable_binary_authorization = var.k8s_options["binary_authorization"]
  enable_kubernetes_alpha     = var.extras["kubernetes_alpha"]
  enable_legacy_abac          = var.enable_legacy_kubeconfig
  logging_service             = var.k8s_options["logging_service"]
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = flatten([formatlist("%s/32", google_compute_address.nat.*.address), var.networks_that_can_access_k8s_api])
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }

  min_master_version = var.k8s_version
  monitoring_service = var.k8s_options["monitoring_service"]
  node_version       = var.node_version

  remove_default_node_pool = var.remove_default_node_pool

  addons_config {
    horizontal_pod_autoscaling {
      disabled = var.k8s_options["enable_hpa"] ? false : true # enabled: y/n
    }

    http_load_balancing {
      disabled = var.k8s_options["enable_http_load_balancing"] ? false : true # enabled: y/n
    }

    kubernetes_dashboard {
      disabled = var.k8s_options["enable_dashboard"] ? false : true # enabled: y/n
    }

    network_policy_config {
      disabled = var.k8s_options["enable_network_policy"] ? false : true # enabled: y/n
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.name}-k8s-pod"
    services_secondary_range_name = "${var.name}-k8s-svc"
  }

  lifecycle {
    ignore_changes = [
      node_pool,
      network,
      subnetwork,
    ]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.extras["maintenance_start_time"]
    }
  }

  master_auth {
    username = "" # Disable basic auth
    password = "" # Disable basic auth
    dynamic "client_certificate_config" {
      for_each = var.client_certificate_config
      content {
        # TF-UPGRADE-TODO: The automatic upgrade tool can't predict
        # which keys might be set in maps assigned here, so it has
        # produced a comprehensive set here. Consider simplifying
        # this after confirming which keys can be set in practice.

        issue_client_certificate = client_certificate_config.value.issue_client_certificate
      }
    }
  }

  network_policy {
    enabled  = var.k8s_options["enable_network_policy"]
    provider = var.k8s_options["enable_network_policy"] ? "CALICO" : "PROVIDER_UNSPECIFIED"
  }

  node_pool {
    name = "default-pool"
  }

  pod_security_policy_config {
    enabled = var.k8s_options["enable_pod_security_policy"]
  }

  dynamic "private_cluster_config" {
    for_each = local.private_cluster
    content {
      enable_private_nodes   = var.private_cluster
      master_ipv4_cidr_block = var.k8s_ip_ranges["master_cidr"]
    }
  }

  timeouts {
    create = var.timeouts["create"]
    update = var.timeouts["update"]
    delete = var.timeouts["delete"]
  }

  depends_on = [
    google_project_iam_member.container_engine_robot,
    google_project_iam_member.cloud_services_account,
    google_project_iam_binding.host_service_agent_iam,
    google_compute_shared_vpc_service_project.spinnaker,
  ]
}

resource "google_container_node_pool" "primary_pool" {
  provider           = google-beta
  name               = "${var.name}-primary-pool"
  cluster            = google_container_cluster.cluster.name
  region             = var.region
  project            = var.project
  initial_node_count = var.node_pool_options["autoscaling_nodes_min"]

  autoscaling {
    min_node_count = var.node_pool_options["autoscaling_nodes_min"]
    max_node_count = var.node_pool_options["autoscaling_nodes_max"]
  }

  management {
    auto_repair  = var.node_pool_options["auto_repair"]
    auto_upgrade = var.node_pool_options["auto_upgrade"]
  }

  max_pods_per_node = var.node_pool_options["max_pods_per_node"]

  node_config {
    disk_size_gb = var.node_options["disk_size"]
    disk_type    = var.node_options["disk_type"]

    # Forces new resource due to computing count :/
    # guest_accelerator {
    #   count = "${length(var.node_options["guest_accelerator"])}"
    #   type = "${var.node_options["guest_accelerator"]}"
    # }
    image_type = var.node_options["image"]

    # labels = "${var.node_labels}" # Forces new resource due to computing count :/
    local_ssd_count = var.extras["local_ssd_count"]
    machine_type    = var.node_options["machine_type"]
    metadata        = var.node_metadata

    # minimum_cpu_platform = "" # TODO
    oauth_scopes    = var.oauth_scopes
    preemptible     = var.node_options["preemptible"]
    service_account = var.service_account == "" ? google_service_account.sa[0].email : var.service_account # See here for explanation of ugly syntax: https://www.terraform.io/upgrade-guides/0-11.html#referencing-attributes-from-resources-with-count-0
    tags = split(
      ",",
      length(var.node_tags) == 0 ? var.name : join(",", var.node_tags),
    )

    # TODO
    # taint {
    #   key = ""
    #   value = ""
    #   effect = ""
    # }
    workload_metadata_config {
      node_metadata = var.extras["metadata_config"]
    }
  }

  depends_on = [
    google_project_iam_member.container_engine_robot,
    google_project_iam_member.cloud_services_account,
    google_project_iam_binding.host_service_agent_iam,
    google_compute_shared_vpc_service_project.spinnaker,
    google_compute_subnetwork.subnet
  ]
}

