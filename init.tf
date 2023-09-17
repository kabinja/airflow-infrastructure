terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.23.1"
    }
  }
}


provider "docker" {
  host = "unix:///var/run/docker.sock"

  registry_auth {
    address  = "https://ghcr.io"
    username = var.ghcr_username
    password = var.ghcr_password
  }
}
