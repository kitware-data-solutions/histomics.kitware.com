terraform {
  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
    }
  }
}

provider "mongodbatlas" {
}

variable "mongodbatlas_org_id" {
  type = string
}

variable "mongodbatlas_project_name" {
  type    = string
  default = "histomics"
}

variable "mongodbatlas_instance_size_name" {
  type    = string
  default = "M10"
}

resource "mongodbatlas_project" "histomics_project" {
  org_id = var.mongodbatlas_org_id
  name   = var.mongodbatlas_project_name
}

resource "mongodbatlas_cluster" "histomics_cluster" {
  provider_name = "AWS"
  project_id    = mongodbatlas_project.histomics_project.id
  name          = "histomics-cluster"
  cluster_type  = "REPLICASET"
  replication_specs {
    num_shards = 1
    regions_config {
      region_name     = "US_EAST_1"
      electable_nodes = 3
      priority        = 7
      read_only_nodes = 0
    }
  }
  backing_provider_name = "AWS"

  provider_instance_size_name = var.mongodbatlas_instance_size_name
  cloud_backup                = true
  mongo_db_major_version      = "7.0"
}

resource "random_password" "mongodb_atlas_password" {
  length  = 20
  special = false
}

resource "mongodbatlas_database_user" "histomics_user" {
  auth_database_name = "admin"
  project_id         = mongodbatlas_project.histomics_project.id
  username           = "histomics"
  password           = random_password.mongodb_atlas_password.result
  roles {
    role_name     = "readWrite"
    database_name = "girder"
  }
}

resource "mongodbatlas_project_ip_access_list" "histomics" {
  project_id = mongodbatlas_project.histomics_project.id
  cidr_block = "0.0.0.0/0" # TODO use public-facing VPC CIDR block
}

locals {
  mongodb_connection_string = format(
    "mongodb+srv://%s:%s@%s",
    mongodbatlas_database_user.histomics_user.username,
    urlencode(mongodbatlas_database_user.histomics_user.password),
    replace(mongodbatlas_cluster.histomics_cluster.connection_strings.0.standard_srv, "mongodb+srv://", "")
  )
}
