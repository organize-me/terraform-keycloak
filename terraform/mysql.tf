resource "mysql_database" "keycloak" {
  name = var.keycloak_db_name
}

resource "mysql_user" "keycloak" {
  user               = var.keycloak_db_username
  host               = var.keycloak_db_user_host
  plaintext_password = var.keycloak_db_password
}

resource "mysql_grant" "keycloak" {
  user       = mysql_user.keycloak.user
  host       = mysql_user.keycloak.host
  database   = mysql_database.keycloak.name
  privileges = ["ALL PRIVILEGES"]
}
