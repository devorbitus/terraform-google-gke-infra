terraform {
  required_version = ">= 0.11.11"
  backend "gcs" {}

  required_providers {
    google      = ">= 1.19.0"
    google-beta = ">= 1.19.0"
  }
}

# Google Provider info
##########################################################
provider "google" {
  version = "~> 1.19"
  region  = "${var.region}"
}

# Get GCP metadata from local gcloud config
##########################################################
data "google_client_config" "gcloud" {}

# VPCs
##########################################################
resource "google_compute_network" "vpc" {
  name                    = "${var.name}"
  project                 = "${var.project}"
  auto_create_subnetworks = "false"
}

# Subnets
##########################################################
resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.name}"
  project                  = "${var.project}"
  network                  = "${google_compute_network.vpc.name}" # https://github.com/terraform-providers/terraform-provider-google/issues/1792
  region                   = "${var.region}"
  description              = "${var.description}"
  ip_cidr_range            = "${var.k8s_ip_ranges["node_cidr"]}"
  private_ip_google_access = true

  # enable_flow_logs = "${var.enable_flow_logs}" # TODO
  secondary_ip_range {
    range_name    = "${var.name}-k8s-pod"
    ip_cidr_range = "${var.k8s_ip_ranges["pod_cidr"]}"
  }

  secondary_ip_range {
    range_name    = "${var.name}-k8s-svc"
    ip_cidr_range = "${var.k8s_ip_ranges["svc_cidr"]}"
  }
}

# Create a Service Account for the GKE Nodes by default
##########################################################
resource "google_service_account" "sa" {
  count        = "${var.service_account == "" ? 1 : 0 }"
  account_id   = "${var.name}"
  display_name = "${var.name} SA"
  project      = "${var.project}"
}

# Create a Service Account key by default
resource "google_service_account_key" "sa_key" {
  count              = "${var.service_account == "" ? 1 : 0 }"
  depends_on         = ["google_project_iam_member.iam"]
  service_account_id = "${google_service_account.sa.name}"
}

# Add IAM Roles to the Service Account
resource "google_project_iam_member" "iam" {
  count   = "${var.service_account == "" ? length(var.service_account_iam_roles) : 0 }"
  member  = "serviceAccount:${google_service_account.sa.email}"
  project = "${var.project}"
  role    = "${element(var.service_account_iam_roles, count.index)}"
}
