provider "google" {
  project     = "indigo-charge-316314"
  region      = "us-central1"
}

terraform {
    backend "gcs" {
   bucket  = "terraform-state-dduha"
 }
}
# # # # # # # # # # # # # # # # # # # # VPC NETWORK # # # # # # # # # # # # # # # # # # # # 
resource "google_compute_network" "vpc_network" {
  name                    = "my-vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public_subnet_1" {
  name          = "public-subnet-1"
  region        = "us-central1"
  ip_cidr_range = "10.0.1.0/28"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_subnetwork" "public_subnet_2" {
  name          = "public-subnet-2"
  region        = "us-central1"
  ip_cidr_range = "10.0.2.0/28"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_subnetwork" "private_subnet_1" {
  name          = "private-subnet-1"
  region        = "us-central1"
  ip_cidr_range = "10.0.3.0/28"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_subnetwork" "private_subnet_2" {
  name          = "private-subnet-2"
  region        = "us-central1"
  ip_cidr_range = "10.0.4.0/28"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_router" "router" {
  name    = "my-router"
  network = google_compute_network.vpc_network.self_link
}

resource "google_compute_router_nat" "cloudnat" {
  name = "testcloudnat"
  router     = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "default" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_compute_network_peering_routes_config" "peering_routes" {
  peering              = google_service_networking_connection.default.peering
  network              = google_compute_network.vpc_network.name
  import_custom_routes = true
  export_custom_routes = true
}
# # # # # # # # # # # # # # # # # # # COMPUTE # # # # # # # # # # # # # # # # # # # # 
resource "google_compute_instance_template" "example_instance_template" {
  name        = "example-instance-template"
  machine_type = "n1-standard-1"
  tags = ["wordpress"]
  disk {
    source_image      = "ubuntu-2004-focal-v20230831"
  }
  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet_1.self_link
  }
  service_account {
    email = google_service_account.testdduha.email
    scopes = ["https://www.googleapis.com/auth/devstorage.read_write"]
  }
  metadata_startup_script = templatefile("wordpress.sh", {
    DB_USER     = google_sql_user.users.name
    DB_PASSWORD = google_sql_user.users.password
    DB_HOST     = google_sql_database_instance.main.private_ip_address
  })
  depends_on = [ google_sql_database_instance.main, google_sql_database.database, google_sql_user.users ]
}

resource "google_compute_region_instance_group_manager" "example_instance_group" {
  name        = "example-instance-group"
  base_instance_name = "example-instance"

  named_port {
    name = "http"
    port = 80
  }
  named_port {
    name = "ssh"
    port = 22
  }
  named_port {
    name = "sql"
    port = 3306
  }

  region                     = "us-central1"
  distribution_policy_zones  = ["us-central1-b", "us-central1-f"]

  version {
    instance_template = google_compute_instance_template.example_instance_template.id
  }

  target_size  = 2
}

resource "google_compute_firewall" "allow-iap" {
  name    = "allow-iap"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags  = ["wordpress"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "sql" {
  name    = "sql"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
  target_tags  = ["wordpress"]
  source_ranges = ["0.0.0.0/0"]
}
# # # # # # # # # # # # # # # # # # # DATABASE # # # # # # # # # # # # # # # # # # # # 
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "main" {
  name             = "main-instance-${random_id.db_name_suffix.hex}"
  database_version = "MYSQL_5_7"
  deletion_protection = false

  depends_on = [google_service_networking_connection.default]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
  }
}

resource "google_sql_database" "database" {
name = "wordpress"
instance = "${google_sql_database_instance.main.name}"
charset = "utf8"
collation = "utf8_general_ci"
}

resource "google_sql_user" "users" {
  name     = "wordpress"
  instance = google_sql_database_instance.main.name
  host = "%"
  password = "wordpress"
}


# # # # # # # # # # # # # # # # # # # LOAD BALANCER # # # # # # # # # # # # # # # # # # # # 

resource "google_compute_firewall" "wordpress_firewall" {
  name    = "wordpress-firewall"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags  = ["wordpress"]
}

resource "google_compute_http_health_check" "http" {
  name = "wordpress-health-check"
  request_path = "/"
  check_interval_sec = 15
  healthy_threshold  = 2
  unhealthy_threshold = 3
  timeout_sec        = 10 
}

resource "google_compute_backend_service" "wordpress-backend-service" {
 name = "wordpress-backend-service"
 health_checks = [google_compute_http_health_check.http.self_link]
 port_name = "http"
 protocol = "HTTP"
 timeout_sec = 300
 backend {
    group = google_compute_region_instance_group_manager.example_instance_group.instance_group
  }
}

resource "google_compute_url_map" "wordpress-url-map" {
 name = "wordpress-url-map"
 default_service = google_compute_backend_service.wordpress-backend-service.self_link
}

resource "google_compute_target_http_proxy" "wordpress-http-proxy" {
 name = "wordpress-http-proxy"
 url_map = google_compute_url_map.wordpress-url-map.self_link
}

resource "google_compute_global_forwarding_rule" "wordpress_https_forwarding_rule" {
  name       = "wordpress-https-forwarding-rule"
  target     = google_compute_target_https_proxy.wordpress_https_proxy.self_link
  ip_address = google_compute_global_address.lb_ip.address
  port_range = "443"
}

resource "google_dns_managed_zone" "wordpress_zone" {
  name        = "wordpress-zone"
  dns_name    = "wordpressdduha.pp.ua."
  description = "DNS Zone for wordpressdduha.pp.ua"
}

resource "google_compute_global_address" "lb_ip" {
  name = "load-balancer-ip"
}

resource "google_dns_record_set" "wordpress_a_record" {
  name         = "wordpressdduha.pp.ua."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.wordpress_zone.name
  rrdatas      = [google_compute_global_address.lb_ip.address]
}

resource "google_dns_record_set" "www_wordpress_cname_record" {
  name         = "www.wordpressdduha.pp.ua."
  type         = "CNAME"
  ttl          = 300
  managed_zone = google_dns_managed_zone.wordpress_zone.name
  rrdatas      = ["wordpressdduha.pp.ua."]
}

resource "google_compute_ssl_certificate" "wordpress_ssl" {
  name        = "wordpress-ssl"
  private_key = file("~/ssl/private.key")
  certificate = file("~/ssl/certificate.crt")
}

resource "google_compute_target_https_proxy" "wordpress_https_proxy" {
  name             = "wordpress-https-proxy"
  url_map          = google_compute_url_map.wordpress-url-map.self_link
  ssl_certificates = [google_compute_ssl_certificate.wordpress_ssl.self_link]
}

# # # # # # # # # # # # # # # # # # # SERVICE ACCOUNT # # # # # # # # # # # # # # # # # # # # 

resource "google_service_account" "testdduha" {
  account_id   = "testdduha"
  display_name = "Test Dduha"
}

resource "google_storage_bucket_iam_member" "testdduha_storage_object_admin" {
  bucket = "wordpress-dduha"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.testdduha.email}"
}

resource "google_storage_bucket_iam_member" "testdduha_storage_object_viewer" {
  bucket = "wordpress-dduha"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.testdduha.email}"
}

resource "google_storage_bucket_iam_member" "testdduha_storage_object_creator" {
  bucket = "wordpress-dduha"
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.testdduha.email}"
}

# # # # # # # # # # # # # # # # # # # # CLOUD FUNCTION # # # # # # # # # # # # # # # # # # # # 
data "google_secret_manager_secret_version_access" "my_secret" {
  secret = "sendgrid-api"
}

resource "google_vpc_access_connector" "connector" {
  name          = "vpc-con"
  region        = "us-central1"
  min_instances = 2
  max_instances = 10
  subnet {
    name = google_compute_subnetwork.private_subnet_1.name
  }
}

resource "google_service_account" "account" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account"
}

resource "google_storage_bucket" "bucket" {
  name                        = "dduha-cloud-fun-bucket"
  location                    = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object" {
  name   = "fun.zip"
  bucket = google_storage_bucket.bucket.name
  source = "fun.zip"
}

resource "google_cloudfunctions2_function" "function" {
  name        = "gcf-function"
  location    = "us-central1"
  description = "a new function"

  build_config {
    runtime     = "python39"
    entry_point = "checkhttp"
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    min_instance_count            = 1
    available_memory              = "256M"
    timeout_seconds               = 60
    service_account_email         = google_service_account.account.email
    vpc_connector                 = google_vpc_access_connector.connector.name
    vpc_connector_egress_settings = "ALL_TRAFFIC"
    environment_variables = {
        SENDGRID_API_KEY  = data.google_secret_manager_secret_version_access.my_secret.secret_data
    }
  }

}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.function.project
  location       = google_cloudfunctions2_function.function.location
  cloud_function = google_cloudfunctions2_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.account.email}"
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  project  = google_cloudfunctions2_function.function.project
  location = google_cloudfunctions2_function.function.location
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "secret_manager_accessor" {
  project  = google_cloudfunctions2_function.function.project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "storage_object_viewer" {
  project  = google_cloudfunctions2_function.function.project
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "cloudfunction_developer" {
  project  = google_cloudfunctions2_function.function.project
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "datastore_user" {
  project  = google_cloudfunctions2_function.function.project
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.account.email}"
}

resource "google_cloud_scheduler_job" "invoke_cloud_function" {
  name        = "invoke-gcf-function"
  description = "Schedule the HTTPS trigger for cloud function"
  schedule    = "*/5 * * * *"
  project     = google_cloudfunctions2_function.function.project
  region      = google_cloudfunctions2_function.function.location

  http_target {
    uri         = google_cloudfunctions2_function.function.service_config[0].uri
    http_method = "POST"
    oidc_token {
      audience              = "${google_cloudfunctions2_function.function.service_config[0].uri}/"
      service_account_email = google_service_account.account.email
    }
  }
}