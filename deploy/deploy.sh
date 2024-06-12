#!/bin/bash

set -e

# Variables
PROJECT_ID='hackathon-cp-project-team-1'
REGION='us-central1'


# Authenticate with GCP using service account key file

# Set the project
gcloud config set project $PROJECT_ID

# Initialize Terraform
terraform init

# Apply Terraform configuration
terraform apply -var="project_id=$PROJECT_ID" \
                -var="region=$REGION" \
                -auto-approve
