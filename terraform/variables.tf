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

variable "ssh_public_key" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "worker_ami_id" {
  type = string
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
}
