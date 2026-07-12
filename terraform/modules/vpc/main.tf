/*
  VPC MODULE
  ----------
  This is the networking foundation. Key GCP concepts vs Azure:

  - GCP VPCs are GLOBAL resources (not regional like Azure VNets). Subnets are regional.
  - We use a custom-mode VPC (not auto-mode) so we control CIDR ranges deliberately —
    this is the standard for any production build, same reasoning as custom VNets in Azure.
  - Private Google Access lets GKE nodes reach Google APIs (Artifact Registry, Cloud Storage,
    Secret Manager) WITHOUT a public IP or NAT — critical for a locked-down cluster.
  - Cloud NAT gives outbound internet to private nodes (e.g. pulling OS packages) without
    ever assigning them public IPs. This is the equivalent of your Azure Firewall SNAT setup,
    but managed and regional.
  - Secondary IP ranges on the subnet are how GKE does VPC-native (alias IP) networking:
    one range for Pods, one for Services. This avoids the old routes-based networking model
    and is what any GKE build should use today.
*/

resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke_subnet" {
  name                     = "${var.project_id}-gke-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata              = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router is required before you can attach Cloud NAT
resource "google_compute_router" "router" {
  name    = "${var.project_id}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_id}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Deny-all-by-default firewall posture, then explicit allows.
# This mirrors zero-trust / least-privilege network design.
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${var.project_id}-deny-all-ingress"
  network   = google_compute_network.vpc.id
  priority  = 65534
  direction = "INGRESS"
  deny {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]
}

# Allow GKE control plane to reach nodes for webhooks/exec (private cluster requirement)
resource "google_compute_firewall" "allow_gke_master" {
  name      = "${var.project_id}-allow-gke-master"
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }
  source_ranges = [var.master_cidr]
}

# Internal service-to-service traffic within the VPC only
resource "google_compute_firewall" "allow_internal" {
  name      = "${var.project_id}-allow-internal"
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}
