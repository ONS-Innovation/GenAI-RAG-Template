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


output "deployment_ip_address" {
  description = "Web URL link"
  value       = google_cloud_run_v2_service.frontend_service.uri
}

output "retrieval_service" {
  description = "Retrieval Service Cloud Run v2 service"
  value       = google_cloud_run_v2_service.retrieval_service.name
}

output "frontend_service" {
  description = "Frontend Service Cloud Run v2 service"
  value       = google_cloud_run_v2_service.frontend_service.name
}

output "Database" {
  description = "Database Name"
  value       = google_sql_database_instance.main.name
}

output "Cloud_SQL_Password" {
  description = "SQL Password"
  value       = google_secret_manager_secret.cloud_sql_password.secret_id
}
