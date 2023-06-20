terraform {
  required_providers {
    random = {
      source = "hashicorp/random"
      version = "3.4.3"
    }

    ssh = {
      source  = "loafoe/ssh"
      version = "1.2.0"
    }
  }
}

provider "random" {
  # Configuration options
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.skip_ssl_verify
}

