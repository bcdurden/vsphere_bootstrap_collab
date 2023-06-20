variable "vsphere_user" {
    type = string
    description = "Username of vsphere environment"
}

variable "vsphere_password" {
    type = string
    description = "Password for username in vsphere environment"
    default = "CT0R0ad$how!"
}

variable "vsphere_server" {
    type = string
    description = "Server URL for vsphere environment"
}

variable "skip_ssl_verify" {
    type = bool
    description = "Flag to disable SSL verification when connecting to vsphere"
    default = true
}

variable "datacenter_name" {
    type = string
    description = "DC name in vsphere"
}

variable "datastore_name" {
    type = string
    description = "Datastore name"
}

variable "cluster_name" {
    type = string
    description = "Cluster name in vsphere"
}

variable "content_library_name" {
    type = string
    description = "The content library name hosting the vm ovf/ova"
}

variable "network_name" {
    type = string
    description = "Network name for cluster"
}

variable "vm_image_name" {
    type = string
    description = "The name of the image in your content library"
}

variable "esxi_hosts" {
    type = list
    description = "List of ESXi hosts"
}
