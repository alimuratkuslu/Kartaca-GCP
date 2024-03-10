terraform {
  required_version = ">= 0.12"
}

provider "google" {
  credentials = file("credentials.json")
  project     = "kartaca-416714"
  region      = "europe-west1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "my-vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "my-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "europe-west1"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  
}

resource "google_compute_router" "router" {
  name    = "my-router"
  network = google_compute_network.vpc_network.self_link
}

resource "google_compute_router_nat" "nat" {
  name             = "my-nat-gateway"
  router           = google_compute_router.router.name
  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance_template" "instance_template" {
  name         = "my-instance-template"
  machine_type = "e2-micro"

  lifecycle {
    prevent_destroy = false
  }
  
  disk {
    source_image      = "debian-cloud/debian-11"
  }

  service_account {
    email  = "kartaca-project@kartaca-416714.iam.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name

    access_config {

    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y apache2
    cat <<EOF > /var/www/html/index.html
    <html>
      <body>
        <h1>Kartaca Projesi Websitesine Hoşgeldiniz!</h1>
      </body>
    </html>
  EOF
}

resource "google_compute_autoscaler" "default" {
  name   = "my-autoscaler"
  zone   = "europe-west1-d"
  target = google_compute_instance_group_manager.my_instance_group.self_link

  autoscaling_policy {
    max_replicas    = 3
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.5
    }
  }
}

resource "google_compute_instance_group_manager" "my_instance_group" {
  name               = "my-instance-group"
  base_instance_name = "my-instance"
  zone               = "europe-west1-d"
  target_size        = 3

  version {
    instance_template  = google_compute_instance_template.instance_template.id
  }

  named_port {
    name = "http"
    port = 80
  }

  named_port {
    name = "https"
    port = 443
  }
}

resource "google_compute_health_check" "default" {
  name               = "http-basic-check"
  check_interval_sec = 5
  healthy_threshold  = 2
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    proxy_header       = "NONE"
    request_path       = "/"
  }
  timeout_sec         = 5
  unhealthy_threshold = 2
}

resource "google_compute_global_address" "default" {
  name       = "lb-ipv4-1"
  ip_version = "IPV4"
}

resource "google_compute_backend_service" "default" {
  name                            = "web-backend-service"
  connection_draining_timeout_sec = 0
  health_checks                   = [google_compute_health_check.default.id]
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  port_name                       = "http"
  protocol                        = "HTTP"
  session_affinity                = "NONE"
  timeout_sec                     = 30
  backend {
    group           = google_compute_instance_group_manager.my_instance_group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "default" {
  name            = "web-map-http"
  default_service = google_compute_backend_service.default.id
}

resource "google_compute_target_http_proxy" "default" {
  name    = "http-lb-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "http-content-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80-80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

resource "google_project_service" "servicenetworking" {
  service = "servicenetworking.googleapis.com"
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "my-vpc-network"
}

resource "google_compute_network" "peering_network" {
  name                    = "private-network"
  auto_create_subnetworks = "false"
}

resource "google_service_networking_connection" "default" {
  network                 = "my-vpc-network"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "my_postgres_instance" {
  name             = "my-postgres-instance"
  database_version = "POSTGRES_13"

  settings {
    tier = "db-f1-micro"  

    ip_configuration {
      ipv4_enabled    = false 
      private_network = google_compute_network.vpc_network.id
      enable_private_path_for_google_cloud_services = true
    }
  }
}