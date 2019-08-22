# GKE Infra

This Terraform module provisions a regional `GKE cluster`, `VPC`, and `Subnet`. Optionally, it can be configured to create a service account with limited permissions for the K8s Nodes if no `service_account` value is provided (see [Use Least Privilege Service Accounts for your Nodes](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#use_least_privilege_sa)).

- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [Basic Usage Example](#basic-usage-example)
  - [Creating a Private Cluster](#creating-a-private-cluster)
  - [Using the Cluster as a TF Provider](#using-the-cluster-as-a-tf-provider)
  - [Upgrading a Cluster](#upgrading-a-cluster)
    - [Update `k8s_version`](#update-k8s_version)
    - [Update `node_version`](#update-node_version)
- [Variables](#variables)
  - [Required Variables](#required-variables)
  - [Optional Variables](#optional-variables)
  - [Optional List Variables](#optional-list-variables)
  - [Optional Map Variables:](#optional-map-variables)
    - [`k8s_ip_ranges`](#k8s_ip_ranges)
    - [`k8s_options`](#k8s_options)
    - [`node_options`](#node_options)
    - [`node_pool_options`](#node_pool_options)
    - [`extras`](#extras)
    - [`timeouts`](#timeouts)
  - [Output Variables](#output-variables)
  - [Links](#links)

## Prerequisites

1. Ensure that you have a version of `terraform` that is at least `v0.11.9` (run `terraform version` to validate).
2. Ensure that your `gcloud` binary is configured and authenticated:

```sh
$ gcloud auth login
```

Alternatively, you can download your `json keyfile` from GCP using [these steps](https://cloud.google.com/sdk/docs/authorizing#authorizing_with_a_service_account) and export the path in your environment like so:

```sh
export GOOGLE_APPLICATION_CREDENTIALS=[JSON_KEYFILE_PATH]
```

3. Set google project where you'd like to deploy the cluster

```sh
export GOOGLE_PROJECT=[PROJECT_NAME]
gcloud config set project PROJECT_ID
```

4. Setup the versioning and backend info in your `main.tf` file:

**NOTE:** these values need to be hard-coded as they cannot be interpolated as variables by Terraform.

```hcl
terraform {
  required_version = ">= 0.11.9"

  required_providers {
    google = ">= 1.19.0"
    google-beta = ">= 1.19.0"
  }

  backend "gcs" {
    bucket = "<BUCKET_NAME>"
    region = "<REGION>"
    prefix = "<PATH>"
  }
}
```

5. Setup your provider info:

**NOTE:** Google-Beta is required to enable certain features (such as private and regional clusters - see [documentation for more info](https://www.terraform.io/docs/providers/google/provider_versions.html)).

```hcl
provider "google" {
  credentials = "${file("${var.credentials_file}")}"
  version     = "~> 1.19"
  region = "${var.region}"
}

provider "google-beta" {
  credentials = "${file("${var.credentials_file}")}"
  version     = "~> 1.19"
  region = "${var.region}"
}
```

## Usage

### Basic Usage Example

```hcl
module "k8s" {
  source  = "git@github.com:dansible/terraform-google_gke_infra.git?ref=v0.5.1"
  name    = "${var.name}"
  project = "${var.project}"
  region  = "${var.region}"
  private_cluster = true  # This will disable public IPs from the nodes
}
```

**NOTE:** All parameters are configurable. Please see [below](#variables) for information on each configuration option.

### Creating a Private Cluster

This module allows the creation of [Private GKE Clusters](https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters) where the nodes do not have public IP addresses. This is achieved using a [GCP Cloud NAT resource](https://cloud.google.com/nat/docs/overview?hl=en_US&_ga=2.47256615.-1497507305.1549638187).

If you were previously using the [NAT Gateway module](https://registry.terraform.io/modules/GoogleCloudPlatform/nat-gateway/google/1.2.2) to create your private cluster, you will need to delete the module from your Terraform config and update this module to at least `v0.5.0`. Re-running `terraform apply` will destroy the old NAT gateway resources and spin up the Cloud NAT router.

If you would prefer to keep using the old NAT Gateway module, you can pass the [`cloud_nat` variable](variables-main.tf#L57) to this module as `false`.

### Using the Cluster as a TF Provider

In the same terraform file, you can use the cluster this module creates by adding the following resources to your `main.tf` file:

```hcl
# Pull Access Token from gcloud client config
# See: https://www.terraform.io/docs/providers/google/d/datasource_client_config.html
data "google_client_config" "gcloud" {}

provider "kubernetes" {
  load_config_file        = false
  host                    = "${module.k8s.endpoint}"
  token                   = "${data.google_client_config.gcloud.access_token}"   # Use the token to authenticate to K8s
  cluster_ca_certificate   = "${base64decode(module.k8s.cluster_ca_certificate)}"
}
```

This uses your local `gcloud` config to get an access token for the cluster. You can then create K8s resources (namespaces, deployments, pods, etc.) on the cluster from within the same Terraform plan.

### Upgrading a Cluster

The module exposes two variables to allow the separate upgrade of the control plane and nodes:

#### Update `k8s_version`

This value configures the version of the Control Plane. It needs to be upgraded first. Generally this operation takes ~15 minutes. Once that is done, re-run `terraform plan` to validate that no further changes are needed by Terraform.

#### Update `node_version`

Once the Control Plane has been updated, set this value to the Master version as you see it in GCP. You need to explicitly state the full version for the nodes (ie `1.11.5-gke.4`). If you don't provide the patch version, (ie, you only use `1.11`), this will cause a permadiff in Terraform.

Finally, run `terraform apply`, and GCP will update the nodes one at a time. This operation can take some time depending on the size of your nodepool. If you find that Terraform times out, simply wait for the operation to complete in GCP and re-run `terraform plan` and `terraform apply` to reconcile the state. You can supply a higher timeout value if needed (the default is 30 minutes - see [timeouts](#timeouts)).

## Workload Identity Config

Clusters will be created with Google's Workload Identity enabled in order to better secure service accounts while [authorizing to Google APIs](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity) because the current alternatives [have significant drawbacks](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#alternatives).

## Variables

For more info, please see the [variables file](variables-main.tf).

### Required Variables

| Variable  | Description                                  |
| :-------- | :------------------------------------------- |
| `name`    | Name to use as a prefix to all the resources. |
| `region`  | The region that hosts the cluster. Each node will be put in a different availability zone in the region for HA. |

### Optional Variables

| Variable               | Description                         | Default                                               |
| :--------------------- | :---------------------------------- | :---------------------------------------------------- |
| `project` | The ID of the google project to which the resource belongs. | Value configured in `gcloud` client. |
| `description` | A description to apply to all resources. | `Managed by Terraform` |
| `enable_legacy_kubeconfig` | Whether to enable authentication using tokens/passwords/certificates. | `false` |
| `k8s_version` | Default K8s version for the Control Plane. | `1.11` |
| `k8s_version_prefix` | If provided and k8s_version is NOT provided, Terraform will only return versions that match the string prefix. For example, 1.11. will match all 1.11 series releases. Since this is just a string match, it's recommended that you append a . after minor versions to ensure that prefixes such as 1.1 don't match versions like 1.12.5-gke.10 accidentally. See [the docs on versioning schema](https://cloud.google.com/kubernetes-engine/versioning-and-upgrades#versioning_scheme) for full details on how version strings are formatted. | `""`|
| `node_version` | Default K8s versions for the Nodes. | `""` |
| `node_version_prefix` | If provided and node_version is NOT provided, Terraform will only return versions that match the string prefix. For example, 1.11. will match all 1.11 series releases. Since this is just a string match, it's recommended that you append a . after minor versions to ensure that prefixes such as 1.1 don't match versions like 1.12.5-gke.10 accidentally. See [the docs on versioning schema](https://cloud.google.com/kubernetes-engine/versioning-and-upgrades#versioning_scheme) for full details on how version strings are formatted. | `""`|
| `private_cluster` | Whether to create a private cluster. This will remove public IPs from your nodes and create a NAT Gateway to allow internet access. | `false` |
| `gcloud_path` | The path to your gcloud client binary. | `gcloud` |
| `service_account` | The service account to be used by the Node VMs. If not specified, a service account will be created with minimum permissions. | `""` |
| `apply_network_policies` | Whether to apply Network Policies, CronJob and PSP resources to the GKE cluster. | `true` |
| `remove_default_node_pool` | Whether to delete the default node pool on creation. Sperate node pool is created by default so don't need default node pool | `true` |
| `cloud_nat` | Whether or not to enable Cloud NAT. This is to retain compatability with clusters that use the old NAT Gateway module. | `true` |
| `nat_bgp_asn` | Local BGP Autonomous System Number (ASN) for the NAT router. | `64514` |

### Optional List Variables
| Variable                 | Description                            | Default                                               |
| :----------------------- | :------------------------------------- | :---------------------------------------------------- |
| `networks_that_can_access_k8s_api` | A list of networks that can access the K8s API in the form of a list of CIDR blocks  in string form like `["192.168.0.1/32","127.1.1.1/32"]`| [`see vars file`](variables-lists.tf) |
| `oauth_scopes` | The set of Google API scopes to be made available on all of the node VMs under the default service account. | [`see vars file`](variables-lists.tf) |
| `node_tags` | The list of instance tags applied to all nodes. If none are provided, the cluster name is used by default. | `[]` |
| `service_account_iam_roles` | A list of roles to apply to the service account if one is not provided. | [`see vars file`](variables-lists.tf) |
| `client_certificate_config` | Whether client certificate authorization is enabled for this cluster. | `[]` |
| `node_metadata` | [MAP] The metadata key/value pairs assigned to instances in the cluster. | `{}` |

### Optional Map Variables:

For maps, all values in each category need to be defined provided in the following format:

```hcl
k8s_ip_ranges = {
  master_cidr = "172.16.0.0/28"
  ...
}
```

#### `k8s_ip_ranges`

A map of the various IP ranges to use for K8s resources.

| Variable      | Description                           | Default                                    |
| :------------ | :------------------------------------ | :----------------------------------------- |
| `master_cidr` | Specifies a private RFC1918 block for the master's VPC.           | `172.16.0.0/28` |
| `pod_cidr`    | The IP address range of the kubernetes pods in this cluster.     | `10.60.0.0/14`   |
| `svc_cidr`    | The IP address range of the kubernetes services in this cluster. | `10.190.16.0/20`   |
| `node_cidr`   | The IP address range of the kubernetes nodes in this cluster.    | `10.190.0.0/22`   |

#### `k8s_options`

Options to configure K8s. These include enabling the dashboard, network policies, monitoring and logging, etc.

| Variable               | Description                           | Default                                               |
| :--------------------- | :------------------------------------ | :---------------------------------------------------- |
| `binary_authorization` | If enabled, all container images will be validated by Google Binary Authorization. | `false` |
| `enable_hpa` | Whether to enable the Horizontal Pod Autoscaling addon. | `true` |
| `enable_http_load_balancing` | Whether to enable the HTTP (L7) load balancing controller addon. | `true` |
| `enable_dashboard` | Whether to enable the k8s dashboard. | `false` |
| `enable_network_policy` | Whether to enable the network policy addon. If enabled, this will also install PSPs and a CronJob to the cluster. | `true` |
| `enable_pod_security_policy` | Whether to enable the PodSecurityPolicy controller for this cluster. | `true` |
| `logging_service` | The logging service that the cluster should write logs to. | `none` |
| `monitoring_service` | The monitoring service that the cluster should write metrics to. | `none` |

#### `node_options`

Options to configure K8s Nodes. These include which OS to use, node sizes, etc.

| Variable       | Description                           | Default                                    |
| :------------- | :------------------------------------ | :----------------------------------------- |
| `disk_size`    | Size of the disk attached to each node, specified in GB.          | `20`            |
| `disk_type`    | Type of the disk attached to each node.                          | `pd-standard`   |
| `image`        | The image type to use for each node.                             | `COS`           |
| `machine_type` | The machine type (RAM, CPU, etc) to use for each node.           | `n1-standard-1` |
| `preemptible`  | Whether to create cheaper nodes that last a maximum of 24 hours. | `true`          |

#### `node_pool_options`

Options to configure the default Node Pool created for the cluster.

| Variable                | Description                                            | Default  |
| :---------------------- | :----------------------------------------------------- | :------- |
| `auto_repair`           | Whether the nodes will be automatically repaired.      | `true`   |
| `auto_upgrade`          | Whether the nodes will be automatically upgraded.      | `true`   |
| `autoscaling_nodes_min` | Minimum number of nodes to create in each zone.        | `1`      |
| `autoscaling_nodes_max` | Maximum number of nodes to create in each zone.        | `3`      |
| `max_pods_per_node`     | The maximum number of pods per node in this node pool. | `110`    |

#### `extras`

Extra options to configure K8s. These are options that are unlikely to change from deployment to deployment.

| Variable                 | Description                           | Default                                               |
| :----------------------- | :------------------------------------ | :---------------------------------------------------- |
| `kubernetes_alpha`       | Enable Kubernetes Alpha features for this cluster.                        | `false` |
| `local_ssd_count`        | The amount of local SSD disks that will be attached to each cluster node. | `0` |
| `maintenance_start_time` | Time window specified for daily maintenance operations.                    | `01:00` |
| `metadata_config`         | How to expose the node metadata to the workload running on the node.      | `SECURE` |

#### `timeouts`

Configurable timeout values for the various cluster operations.

| Variable  | Description                                      | Default  |
| :-------- | :----------------------------------------------- | :------- |
| `create`  | The default timeout for a cluster create operation. | `20m` |
| `update`  | The default timeout for a cluster update operation. | `30m` |
| `delete`  | The default timeout for a cluster delete operation. | `20m` |

### Output Variables

| Variable                | Description                       |
| :---------------------- | :-------------------------------- |
| `cluster_name`          | The name of the cluster created by this module |
| `kubeconfig`            | A generated kubeconfig to authenticate with K8s. |
| `endpoint`              | The API server's endpoint. |
| `cluster_ca_certificate`| The CA certificate used to create the cluster. |
| `client_certificate`    | The client certificate to use for accessing the API (only valid if `enable_legacy_kubeconfig` is set to `true`). |
| `client_key`            | The client key to use for accessing the API (only valid if `enable_legacy_kubeconfig` is set to `true`). |
| `network_name`          | The name of the network created by this module. Useful for passing to other resources you want to create on the same VPC. |
| `subnet_name`           | The name of the subnet created by this module. Useful for passing to other resources you want to create on the same subnet. |
| `k8s_ip_ranges`         | The ranges defined in the GKE cluster |
| `instace_urls`          | The unique URLs of the K8s Nodes in GCP. |
| `service_account`       | The email of the service account created by or supplied to this module. |
| `service_account_key`   | The key for the service account created by this module. |
| `cloud_nat_adddress`    | The IP address of the cloud nat address created when private cluster is used with cloud nat. |

### Links

- https://www.terraform.io/docs/providers/google/r/container_cluster.html
- https://www.terraform.io/docs/providers/google/r/compute_network.html
- https://www.terraform.io/docs/providers/google/r/compute_subnetwork.html
- https://www.terraform.io/docs/providers/google/d/datasource_google_service_account.html
- https://www.terraform.io/docs/providers/google/r/compute_route.html
- https://www.terraform.io/docs/provisioners/null_resource.html

