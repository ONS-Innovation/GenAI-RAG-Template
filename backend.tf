terraform {
  backend "gcs" {
    bucket = "terraform-gemini-bucket-${BUCKET_NAME}"
    prefix = "terraform/state"
  }
}
