terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 3.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">= 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "europe-west2"
}

variable "project_id" {
  description = "The project ID to deploy to"
  type        = string
}

resource "random_id" "id" {
  byte_length = 4
}

resource "google_storage_bucket" "gemini_bucket" {
  name          = "terraform-gemini-bucket-${random_id.id.hex}"
  location      = "europe-west2"
  force_destroy = false
}

output "bucket_name" {
  value = google_storage_bucket.gemini_bucket.name
}
