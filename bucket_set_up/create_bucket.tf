// create_bucket.tf
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
