
locals {
  airflow_image = "airflow:2.7.0"

  airflow_environment = [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow-postgres/airflow",
    "AIRFLOW__CORE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@airflow-postgres/airflow",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@airflow-postgres/airflow",
    "AIRFLOW__CELERY__BROKER_URL=redis://:@airflow-redis:6379/0",
    "AIRFLOW__CORE__FERNET_KEY=",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=true",
    "AIRFLOW__CORE__LOAD_EXAMPLES=true",
    "AIRFLOW__API__AUTH_BACKENDS=airflow.api.auth.backend.basic_auth,airflow.api.auth.backend.session",
    "AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK=true"
  ]

  airflow_volumes = [
    {
      container_path = "${local.envs.airflow_project_dir}/dags"
      host_path      = "/opt/airflow/dags"
    },
    {
      container_path = "${local.envs.airflow_project_dir}/logs"
      host_path      = "/opt/airflow/logs"
    },
    {
      container_path = "${local.envs.airflow_project_dir}/config"
      host_path      = "/opt/airflow/config"
    },
    {
      container_path = "${local.envs.airflow_project_dir}/plugins"
      host_path      = "/opt/airflow/plugins"
    }
  ]
}

resource "docker_network" "airflow_network" {
  name   = "airflow-network"
  driver = "bridge"
}

resource "docker_container" "postgres" {
  name    = "airflow-postgres"
  image   = "postgres:13"
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=airflow",
    "POSTGRES_DB=airflow",
    "POSTGRES_PASSWORD=airflow"
  ]

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  volumes {
    container_path = "/var/lib/postgresql/data"
    host_path      = local.envs.database_data_dir
  }

  healthcheck {
    test         = ["CMD", "pg_isready", "-U", "airflow"]
    interval     = "10s"
    retries      = 5
    start_period = "5s"
  }
}

resource "docker_container" "redis" {
  name    = "airflow-redis"
  image   = "redis:latest"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  healthcheck {
    test         = ["CMD", "redis-cli", "ping"]
    interval     = "10s"
    timeout      = "30s"
    retries      = 50
    start_period = "30s"
  }
}

resource "docker_container" "init" {
  name  = "airflow-init"
  image = local.airflow_image
  env = concat(local.airflow_environment, [
    "_AIRFLOW_DB_MIGRATE=true",
    "_AIRFLOW_WWW_USER_CREATE=true",
    "_AIRFLOW_WWW_USER_USERNAME=airflow",
    "_AIRFLOW_WWW_USER_PASSWORD=airflow",
    "_PIP_ADDITIONAL_REQUIREMENTS="
  ])
  restart    = "unless-stopped"
  entrypoint = ["/bin/bash"]
  command    = ["c", file("./init.sh")]
  user       = "0:0"

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  dynamic "volumes" {
    for_each = toset(local.airflow_volumes)
    content {
      container_path = volumes.value.container_path
      host_path      = volumes.value.host_path
    }
  }


  volumes {
    container_path = "/sources"
    host_path      = "${local.envs.airflow_project_dir}/sources"
  }
}

resource "docker_container" "webserver" {
  name    = "airflow-webserver"
  image   = local.airflow_image
  env     = local.airflow_environment
  restart = "unless-stopped"
  command = ["webserver"]

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  dynamic "volumes" {
    for_each = toset(local.airflow_volumes)
    content {
      container_path = volumes.value.container_path
      host_path      = volumes.value.host_path
    }
  }

  ports {
    internal = "8080"
    external = "8080"
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:8080/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  depends_on = [docker_container.postgres, docker_container.redis, docker_container.init]
}

resource "docker_container" "scheduler" {
  name    = "airflow-scheduler"
  image   = local.airflow_image
  env     = local.airflow_environment
  restart = "unless-stopped"
  command = ["scheduler"]

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  dynamic "volumes" {
    for_each = toset(local.airflow_volumes)
    content {
      container_path = volumes.value.container_path
      host_path      = volumes.value.host_path
    }
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:8974/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  depends_on = [docker_container.postgres, docker_container.redis, docker_container.init]
}

resource "docker_container" "worker" {
  name    = "airflow-worker"
  image   = local.airflow_image
  env     = concat(local.airflow_environment, ["DUMB_INIT_SETSID=0"])
  restart = "unless-stopped"
  command = ["celery", "worker"]

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  dynamic "volumes" {
    for_each = toset(local.airflow_volumes)
    content {
      container_path = volumes.value.container_path
      host_path      = volumes.value.host_path
    }
  }
  healthcheck {
    test         = ["CMD-SHELL", "celery --app airflow.providers.celery.executors.celery_executor.app inspect ping -d \"celery@$${HOSTNAME}\" || celery --app airflow.executors.celery_executor.app inspect ping -d \"celery@$${HOSTNAME}\""]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  depends_on = [docker_container.postgres, docker_container.redis, docker_container.init]
}

resource "docker_container" "triggerer" {
  name    = "airflow-triggerer"
  image   = local.airflow_image
  env     = local.airflow_environment
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  dynamic "volumes" {
    for_each = toset(local.airflow_volumes)
    content {
      container_path = volumes.value.container_path
      host_path      = volumes.value.host_path
    }
  }
  healthcheck {
    test         = ["CMD-SHELL", "airflow jobs check --job-type TriggererJob --hostname \"$${HOSTNAME}\""]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  depends_on = [docker_container.postgres, docker_container.redis, docker_container.init]
}
