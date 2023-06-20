resource "vsphere_virtual_machine" "jumpbox" {
  name                 = "jumpbox-rancher"
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  folder               = "${data.vsphere_datacenter.datacenter.name}/rancher"

  wait_for_guest_net_timeout = 5

  num_cpus         = 4
  memory           = 8192
  network_interface {
    network_id = data.vsphere_network.network.id
  }

  clone {
    template_uuid = data.vsphere_content_library_item.ubuntu_ovf.id
  }

  disk {
    label            = "disk0"
    size             = 120
  }
  cdrom {
    client_device = true
  }

  vapp {
    properties = {
      "hostname" = "jumpbox-rancher",
      "user-data" = base64encode( <<EOT
        #cloud-config
        package_update: true
        hostname: jumpbox-rancher
        password: supersecretpassword
        chpasswd: { expire: False }
        ssh_pwauth: True
        packages:
        - make
        - jq
        - libguestfs-tools
        runcmd:
        - snap install helm --classic
        - snap install kubectl --classic
        - snap install terraform --classic
        - mkdir -p /home/ubuntu/.kube
        - touch ~/.kube/config
        - wget https://github.com/sigstore/cosign/releases/download/v1.12.1/cosign-linux-amd64
        - install cosign-linux-amd64 /usr/local/bin/cosign
        - rm cosign-linux-amd64
        - wget https://github.com/sunny0826/kubecm/releases/download/v0.21.0/kubecm_v0.21.0_Linux_x86_64.tar.gz
        - tar xvf kubecm_v0.21.0_Linux_x86_64.tar.gz
        - install kubecm /usr/local/bin/kubecm
        - rm LICENSE README.md kubecm kubecm_v0.21.0_Linux_x86_64.tar.gz
        - git clone https://github.com/ahmetb/kubectx /opt/kubectx
        - ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
        - ln -s /opt/kubectx/kubens /usr/local/bin/kubens
        - wget -O- https://carvel.dev/install.sh > install.sh
        - sudo bash install.sh
        - rm install.sh
        - wget https://github.com/mikefarah/yq/releases/download/v4.30.1/yq_linux_amd64
        - sudo install yq_linux_amd64 /usr/local/bin/yq
        - rm yq_linux_amd64
        ssh_authorized_keys: 
        - ${tls_private_key.global_key.public_key_openssh}
      EOT
      )  
    }
  }
}
