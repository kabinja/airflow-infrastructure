terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.23.1"
    }
  }
}

variable "ghcr_username" {}
variable "ghcr_password" {} 


provider "docker" {
  host = "unix:///var/run/docker.sock"

  registry_auth {
    address  = "https://ghcr.i"
    username = var.ghcr_username
    password = var.ghcr_password
  }
}
