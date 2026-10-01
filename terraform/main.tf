terraform {
  required_version = ">= 1.3.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"
    }
    mysql = {
      source  = "petoju/mysql"
      version = "= 3.0.72"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.5.2"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

data "docker_network" "network" {
  name = var.docker_network
}

provider "mysql" {
  endpoint = "${var.mysql_host}:${var.mysql_port}"
  username = var.mysql_root_username
  password = var.mysql_root_password
}
