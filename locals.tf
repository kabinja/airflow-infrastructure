variable "airflow_env" {}
variable "ghcr_username" {}
variable "ghcr_password" {} 

locals {
  envs = { for tuple in regexall("(.*)=(.*)", file(var.airflow_env)) : tuple[0] => tuple[1] }
}