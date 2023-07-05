data "vsphere_datacenter" "datacenter" {
  name = var.datacenter_name
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = var.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource random_shuffle "hosts" {
    input = var.esxi_hosts
    result_count = 1
}

data "vsphere_host" "host" {
  name          = random_shuffle.hosts.result[0]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_content_library" "content_library" {
  name = var.content_library_name
}

data "vsphere_content_library_item" "vm_ovf" {
  name       = var.vm_image_name
  type       = "ovf"
  library_id = data.vsphere_content_library.content_library.id
}