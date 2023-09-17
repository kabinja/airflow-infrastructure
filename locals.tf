variable "airflow_env" {}

locals {
  envs = { for tuple in regexall("(.*)=(.*)", file(var.airflow_env)) : tuple[0] => tuple[1] }
}