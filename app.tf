/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  project_id   = "hackathon-cp-project-team-1"
  organization = "backstage-dummy-org"
  repo         = "RAG-Demo-SDP" 
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


# Creates the Service Account to be used by Cloud Run
resource "google_service_account" "github_actions" {
  project      = local.project_id
  account_id   = "github-actions"
  display_name = "Service Account for Cloud Run"

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${local.organization}/${local.repo}"
}

}

# # Applies permissions to the Cloud Run SA
resource "google_project_iam_member" "allrun" {
  for_each = toset([
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/run.invoker",
    "roles/aiplatform.user",
    "roles/iam.serviceAccountTokenCreator",
  ])

  project = module.project-services.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.runsa.email}"
}

# Deploys a service to be used for the database
resource "google_cloud_run_v2_service" "retrieval_service" {
  name     = "retrieval-service-${random_id.id.hex}"
  location = var.region
  project  = module.project-services.project_id

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
        value = module.project-services.project_id
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

# Deploys a service to be used for the frontend
resource "google_cloud_run_v2_service" "frontend_service" {
  name     = "frontend-service-${random_id.id.hex}"
  location = var.region
  project  = module.project-services.project_id

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

# # Set the frontend service to allow all users
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

# # Trigger the database init step from the retrieval service
# # Manual Run: curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" {run_service}/data/import

# tflint-ignore: terraform_unused_declarations
data "http" "database_init" {
  url    = "${google_cloud_run_v2_service.retrieval_service.uri}/data/import"
  method = "GET"
  request_headers = {
    Accept = "application/json"
  Authorization = "Bearer ${data.google_service_account_id_token.oidc.id_token}" }

  depends_on = [
    google_sql_database.database,
    google_cloud_run_v2_service.retrieval_service,
    data.google_service_account_id_token.oidc,
  ]
}
