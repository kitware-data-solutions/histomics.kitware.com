terraform {
  cloud {
    organization = "kitware"

    workspaces {
      name = "histomics-demo"
    }
  }

  required_providers {
    mongodbatlas = {
      source = "mongodb/mongodbatlas"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Deployment = "histomics.kitware.com"
    }
  }
}

provider "mongodbatlas" {}
