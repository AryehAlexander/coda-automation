provider "google" {
  alias   = "google_east4"
  project = "o1labs-192920"
  region  = "us-east4"
}

### Testnets

locals {
  east4_prometheus_helm_values = {
    server = {
      global = {
        external_labels = {
          origin_prometheus = "east4-prometheus"
        }
      }
      persistentVolume = {
        size = "50Gi"
      }
      remoteWrite = [
        {
          url = jsondecode(data.aws_secretsmanager_secret_version.current_prometheus_remote_write_config.secret_string)["remote_write_uri"]
          basic_auth = {
            username = jsondecode(data.aws_secretsmanager_secret_version.current_prometheus_remote_write_config.secret_string)["remote_write_username"]
            password = jsondecode(data.aws_secretsmanager_secret_version.current_prometheus_remote_write_config.secret_string)["remote_write_password"]
          }
          write_relabel_configs = [
            {
              source_labels: ["__name__"]
              regex: "(container.*|Coda.*)"
              action: "keep"
            }
          ]
        }
      ]
    }
  }
}

resource "google_container_cluster" "coda_cluster_east4" {
  provider = google.google_east4
  name     = "coda-infra-east4"
  location = "us-east4"
  min_master_version = "1.15"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "east4_primary_nodes" {
  provider = google.google_east4
  name       = "coda-infra-east4"
  location   = "us-east4"
  cluster    = google_container_cluster.coda_cluster_east4.name
  node_count = 4
  autoscaling {
    min_node_count = 0
    max_node_count = 15
  }
  node_config {
    preemptible  = false
    machine_type = "n1-standard-16"
    disk_size_gb = 100

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

provider helm {
  alias = "helm_east4"
  kubernetes {
    host                   = "https://${google_container_cluster.coda_cluster_east4.endpoint}"
    client_certificate     = base64decode(google_container_cluster.coda_cluster_east4.master_auth[0].client_certificate)
    client_key             = base64decode(google_container_cluster.coda_cluster_east4.master_auth[0].client_key)
    cluster_ca_certificate = base64decode(google_container_cluster.coda_cluster_east4.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
    load_config_file       = false
  }
}

resource "helm_release" "east4_prometheus" {
  provider  = helm.helm_east4
  name      = "east4-prometheus"
  chart     = "stable/prometheus"
  namespace = "default"
  values = [
    yamlencode(local.east4_prometheus_helm_values)
  ]
  wait       = true
  depends_on = [google_container_cluster.coda_cluster_east4]
  force_update  = true
}

## Buildkite

resource "google_container_cluster" "buildkite_infra_east4" {
  provider = google.google_east4
  name     = "buildkite-infra-east4"
  location = "us-east4"
  min_master_version = "1.15"

  node_locations = [
    "us-east4-a",
    "us-east4-b",
    "us-east4-c"
  ]

  remove_default_node_pool = true
  initial_node_count       = 1
  
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "east4_compute_nodes" {
  provider = google.google_east4
  name       = "buildkite-east4-compute"
  location   = "us-east4"
  cluster    = google_container_cluster.buildkite_infra_east4.name

  # total nodes provisioned = node_count * # of AZs
  node_count = 5
  autoscaling {
    min_node_count = 2
    max_node_count = 5
  }
  node_config {
    preemptible  = true
    machine_type = "c2-standard-16"
    disk_size_gb = 500

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}