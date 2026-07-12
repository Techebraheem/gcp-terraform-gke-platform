resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region 

  network    = var.network_id
  subnetwork = var.subnet_id

  # creates the control plane
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = false
    enable_private_endpoint = false 
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.authorized_network_cidr
      display_name = "office-and-cloudbuild"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2 - Cilium-based, enables network policy + flow logs

  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED" # unspecified = uses Dataplane V2's built-in enforcement
  }

  release_channel {
    channel = "REGULAR" # auto-patches minor versions on a predictable cadence — standard practice
  }

  # Cluster-level logging/monitoring — feeds Cloud Operations Suite automatically
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus {
      enabled = true # Google Managed Prometheus — scrape without running your own Prometheus
    }
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE" # enforces the policy from artifact-registry module
  }
}

resource "google_container_node_pool" "app_pool" {
  name     = "app-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # No public IP on nodes; nodes only have RFC1918 addresses
    service_account = var.node_sa_email
    oauth_scopes     = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity to function
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      pool = "app"
    }
  }
}
