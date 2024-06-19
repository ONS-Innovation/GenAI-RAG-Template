locals {
  project_id   = "hackathon-cp-project-team-1"
  organization = "backstage-dummy-org"
  repo         = "GenAI-RAG-Template"
}

resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = local.project_id
  workload_identity_pool_id = "gemini-rag"
  display_name              = "demo-test"
  description               = "Identity pool for GitHub deployments"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "gemini-rag-provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository_owner==\"${local.organization}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  project      = local.project_id
  account_id   = "github-actions"
  display_name = "Service Account used for GitHub Actions"
}

resource "google_service_account" "runsa" {
  project      = local.project_id
  account_id   = "genai-rag-run-sa-${random_id.id.hex}"
  display_name = "Service Account for Cloud Run"
}

resource "google_project_service" "wif_api" {
  for_each = toset([
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/1054015443281/locations/global/workloadIdentityPools/gemini-rag/attribute.repository/backstage-dummy-org/GenAI-RAG-Template"
}

resource "google_project_iam_member" "allrun" {
  for_each = toset([
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/run.invoker",
    "roles/aiplatform.user",
    "roles/iam.serviceAccountTokenCreator",
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_cloud_run_v2_service" "retrieval_service" {
  name     = "retrieval-service-${random_id.id.hex}"
  location = var.region
  project  = local.project_id

  template {
    service_account = google_service_account.runsa.email
    labels          = var.labels

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.retrieval_container
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
      env {
        name  = "APP_HOST"
        value = "0.0.0.0"
      }
      env {
        name  = "APP_PORT"
        value = "8080"
      }
      env {
        name  = "DB_KIND"
        value = "cloudsql-postgres"
      }
      env {
        name  = "DB_PROJECT"
        value = local.project_id
      }
      env {
        name  = "DB_REGION"
        value = var.region
      }
      env {
        name  = "DB_INSTANCE"
        value = google_sql_database_instance.main.name
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.database.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.service.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.cloud_sql_password.secret_id
            version = "latest"
          }
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service" "frontend_service" {
  name     = "frontend-service-${random_id.id.hex}"
  location = var.region
  project  = local.project_id

  template {
    service_account = google_service_account.runsa.email
    labels          = var.labels

    containers {
      image = var.frontend_container
      env {
        name  = "SERVICE_URL"
        value = google_cloud_run_v2_service.retrieval_service.uri
      }
      env {
        name  = "SERVICE_ACCOUNT_EMAIL"
        value = google_service_account.runsa.email
      }
      env {
        name  = "ORCHESTRATION_TYPE"
        value = "langchain-tools"
      }
      env {
        name  = "DEBUG"
        value = "False"
      }
    }
  }
}

resource "google_cloud_run_service_iam_member" "noauth_frontend" {
  location = google_cloud_run_v2_service.frontend_service.location
  project  = google_cloud_run_v2_service.frontend_service.project
  service  = google_cloud_run_v2_service.frontend_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

data "google_service_account_id_token" "oidc" {
  target_audience = google_cloud_run_v2_service.retrieval_service.uri
}

data "http" "database_init" {
  url    = "${google_cloud_run_v2_service.retrieval_service.uri}/data/import"
  method = "GET"
  request_headers = {
    Accept = "application/json"
    Authorization = "Bearer ${data.google_service_account_id_token.oidc.id_token}"
  }

  depends_on = [
    google_sql_database.database,
    google_cloud_run_v2_service.retrieval_service,
    data.google_service_account_id_token.oidc,
  ]
}
