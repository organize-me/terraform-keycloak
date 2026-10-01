resource "docker_image" "keycloak" {
  name         = var.keycloak_image
  keep_locally = true
}

resource "docker_container" "keycloak" {
  image        = docker_image.keycloak.image_id
  name         = var.keycloak_container_name
  hostname     = "keycloak"
  restart      = "unless-stopped"
  network_mode = "bridge"

  command = [
    "start-dev",
    "--http-relative-path",
    var.keycloak_http_relative_path,
  ]

  env = concat([
    "TZ=${var.timezone}",
    "KC_DB=mysql",
    "KC_DB_URL_HOST=${var.keycloak_db_host}",
    "KC_DB_URL_PORT=${var.keycloak_db_port}",
    "KC_DB_URL_DATABASE=${mysql_database.keycloak.name}",
    "KC_DB_USERNAME=${var.keycloak_db_username}",
    "KC_DB_PASSWORD=${var.keycloak_db_password}",
    "KC_DB_URL_PROPERTIES=?connectTimeout=30",
    "KC_PROXY=${var.keycloak_proxy}",
    ], var.keycloak_admin_password == null ? [] : [
    "KEYCLOAK_ADMIN=${var.keycloak_admin_username}",
    "KEYCLOAK_ADMIN_PASSWORD=${var.keycloak_admin_password}",
  ])

  ports {
    internal = 8080
    external = var.keycloak_external_port
  }

  networks_advanced {
    name    = data.docker_network.network.name
    aliases = ["keycloak"]
  }

  depends_on = [
    mysql_grant.keycloak,
  ]
}

output "keycloak_url" {
  description = "URL for the Keycloak HTTP endpoint"
  value       = "http://localhost:${var.keycloak_external_port}${var.keycloak_http_relative_path}"
}
