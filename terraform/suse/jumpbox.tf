resource "vsphere_virtual_machine" "jumpbox" {
  name                 = "jumpbox-suse"
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  folder               = var.vm_folder

  wait_for_guest_net_timeout = 5

  num_cpus         = 4
  memory           = 8192
  network_interface {
    network_id = data.vsphere_network.network.id
  }

  clone {
    template_uuid = data.vsphere_content_library_item.vm_ovf.id
  }

  disk {
    label            = "disk0"
    size             = 120
  }
  cdrom {
    client_device = true
  }
  extra_config = {
      "guestinfo.userdata"          = base64encode( <<EOT
        #cloud-config
        package_update: true
        hostname: jumpbox-suse
        password: supersecretpassword
        chpasswd: { expire: False }
        ssh_pwauth: True
        packages: []
        runcmd: []
        ssh_authorized_keys: 
        - ${tls_private_key.global_key.public_key_openssh}
      EOT
      )  
      "guestinfo.userdata.encoding" = "base64"
      "guestinfo.metadata"          = base64encode( <<EOT
        network:
          version: 2
          ethernets:
            eth0:
              addresses:
                - 10.1.1.4/24
              gateway4: 10.1.1.1
              nameservers:
                addresses: [8.8.8.8]
      EOT
      )
      "guestinfo.metadata.encoding" = "base64"
    }
}
