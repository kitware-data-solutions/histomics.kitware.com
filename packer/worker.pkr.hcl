packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.9"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "amazon-ebs" "histomics-worker" {
  instance_type = "t3.xlarge"
  region        = "us-east-1"
  source_ami    = "ami-0fc5d935ebf8bc3bc"
  ssh_username  = "ubuntu"
  ami_name      = "${source.name}-${formatdate("YYYY.MM.DD-hh.mm.ss", timestamp())}"
}

build {
  name = "worker-release"

  source "source.amazon-ebs.histomics-worker" {
    name = "worker-release"
  }

  provisioner "ansible" {
    playbook_file = "${path.root}/provision/ec2-playbook.yml"

    user      = build.User
    use_proxy = false
  }
}
