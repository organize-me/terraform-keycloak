terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.3"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

resource "docker_network" "test" {
  name = var.docker_network
}

resource "docker_image" "mysql" {
  name         = var.mysql_image
  keep_locally = true
}

resource "docker_container" "mysql" {
  image        = docker_image.mysql.image_id
  name         = "keycloak-test-mysql"
  hostname     = "mysql"
  network_mode = "bridge"
  wait         = true
  wait_timeout = 120

  env = [
    "TZ=${var.timezone}",
    "MYSQL_ROOT_PASSWORD=${var.mysql_root_password}",
  ]

  healthcheck {
    test     = ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p\"$MYSQL_ROOT_PASSWORD\" --silent"]
    interval = "5s"
    timeout  = "3s"
    retries  = 24
  }

  ports {
    internal = 3306
    external = var.mysql_external_port
  }

  networks_advanced {
    name    = docker_network.test.name
    aliases = ["mysql"]
  }
}

resource "docker_image" "localstack" {
  name         = var.s3_compatible_image
  keep_locally = true
}

resource "docker_container" "localstack" {
  image        = docker_image.localstack.image_id
  name         = "keycloak-test-s3"
  hostname     = "localstack"
  network_mode = "bridge"
  wait         = true

  env = [
    "SERVICES=s3",
    "DEFAULT_REGION=us-east-1",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
    interval = "5s"
    timeout  = "3s"
    retries  = 12
  }

  ports {
    internal = 4566
    external = var.s3_compatible_external_port
  }

  networks_advanced {
    name    = docker_network.test.name
    aliases = ["localstack"]
  }
}

resource "docker_image" "aws_cli" {
  name         = var.aws_cli_image
  keep_locally = true
}

resource "null_resource" "create_backup_bucket" {
  triggers = {
    localstack_id = docker_container.localstack.id
    bucket        = var.backup_s3_bucket
  }

  provisioner "local-exec" {
    command = "docker run --rm --network ${docker_network.test.name} --env AWS_ACCESS_KEY_ID=test --env AWS_SECRET_ACCESS_KEY=test --env AWS_DEFAULT_REGION=us-east-1 ${docker_image.aws_cli.name} s3 mb --endpoint-url http://localstack:4566 s3://${var.backup_s3_bucket}"
  }
}