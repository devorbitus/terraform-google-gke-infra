# Create an external NAT IP
resource "google_compute_address" "nat" {
  count   = (var.private_cluster && var.cloud_nat) ? 1 : 0
  name    = "${var.name}-nat"
  project = var.project
  region  = var.region
}

# Create a NAT router so the nodes can reach DockerHub, etc
resource "google_compute_router" "router" {
  count       = (var.private_cluster && var.cloud_nat) ? 1 : 0
  name        = var.name
  network     = (var.shared_vpc_name != "") ? data.google_compute_network.shared-network[0].self_link : google_compute_network.vpc[0].self_link
  project     = var.project
  region      = var.region
  description = var.description

  bgp {
    asn = var.nat_bgp_asn
  }
}

resource "google_compute_router_nat" "nat" {
  count                              = (var.private_cluster && var.cloud_nat) ? 1 : 0
  name                               = var.name
  project                            = var.project
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat[0].self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      "${var.name}-k8s-pod",
      "${var.name}-k8s-svc",
    ]
  }
}

# For old version of NAT Gateway (VM)
# Route traffic to the Masters through the default gateway. This fixes things like kubectl exec and logs
##########################################################
resource "google_compute_route" "gtw_route" {
  count            = (var.private_cluster && var.cloud_nat) ? 1 : 0
  name             = var.name
  depends_on       = [google_compute_subnetwork.subnet]
  dest_range       = google_container_cluster.cluster.endpoint
  network          = google_compute_network.vpc[0].name
  next_hop_gateway = "default-internet-gateway"
  priority         = 700
  project          = var.project
  tags = split(
    ",",
    length(var.node_tags) == 0 ? var.name : join(",", var.node_tags),
  )
}

