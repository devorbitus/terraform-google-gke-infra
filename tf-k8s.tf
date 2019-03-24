# Setup cluster credentials
##########################################################
resource "null_resource" "k8s_credentials" {
  count = "${var.deploy["network_policy"] || var.deploy["pod_security_policy"] == 1 ? 1 : 0 }"

  triggers {
    host                   = "${md5(var.name)}"
    endpoint               = "${md5(google_container_cluster.cluster.endpoint)}"
    cluster_ca_certificate  = "${md5(google_container_cluster.cluster.master_auth.0.cluster_ca_certificate)}"
  }

  provisioner "local-exec" {
    command = <<EOF
set -o errexit
set -o pipefail
gcloud container clusters get-credentials "${var.name}" --region="${var.region}" --project="${var.project}"
set +o errexit
CRB_OUTPUT=$$(kubectl create clusterrolebinding "$$(gcloud config get-value account)" --clusterrole=cluster-admin --user="$$(gcloud config get-value account)" 2>&1)
set -o errexit
if echo "$$CRB_OUTPUT" | grep -E 'created|AlreadyExists' ; then
  exit 0 ;
else
  exit 1
fi
EOF
  }
}

# Apply network policies
##########################################################
# TODO

# Apply PodSecurityPolicies
##########################################################
# TODO