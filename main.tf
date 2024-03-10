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

# 3. Cloud Router and NAT Gateway
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

# 4. Instance template
resource "google_compute_instance_template" "instance_template" {
  name         = "my-instance-template"
  machine_type = "e2-micro"

  lifecycle {
    prevent_destroy = false
  }
  
  disk {
    source_image      = "debian-cloud/debian-11"
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

