terraform {
  required_providers {
    crusoe = {
      source = "registry.terraform.io/crusoecloud/crusoe"
    }
  }
}

locals {
  my_ssh_privkey_path="/Users/amrragab/.ssh/id_ed25519"
  my_ssh_pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdc3Aaj8RP7ru1oSxUuehTRkpYfvxTxpvyJEZqlqyze amrragab@MBP-Amr-Ragab.local"
  headnode_instance_type="a40.1x"
  deploy_location = "us-northcentral1-a"
}

resource "crusoe_storage_disk" "headnode_disk" {
    name = "headnode-disk"
    size = "512GiB"
    location = local.deploy_location
}
resource "crusoe_compute_instance" "headnode_vm1" {
    name = "crusoe-headnode-1"
    type = local.headnode_instance_type
    ssh_key = local.my_ssh_pubkey
    location = local.deploy_location
    image = "nvidia-docker:latest"
    disks = [ 
      crusoe_storage_disk.headnode_disk
    ]
    startup_script = file("headnode-bootstrap.sh")

    provisioner "file" {
      content      = local.my_ssh_pubkey
      destination = "/root/provision.key"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "remote-exec" {
      inline = [
        "echo export CRUSOE_ACCESS_KEY_ID=${var.access_key} >> /etc/profile.d/crusoe-cli.sh",
        "echo export CRUSOE_SECRET_KEY=${var.secret_key} >> /etc/profile.d/crusoe-cli.sh",
        "echo export CRUSOE_SSH_PUBLIC_KEY_FILE=/root/provision.key >> /etc/profile.d/crusoe-cli.sh",
        "chmod +x /etc/profile.d/crusoe-cli.sh"
      ]
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "local-exec" {
      command = "crusoe compute vms get ${self.name} -f json >> /tmp/metadata.${self.name}.json"
    }
    provisioner "file" {
      source      = "/tmp/metadata.${self.name}.json"
      destination = "/root/metadata.json"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "slurm-crusoe-startup.sh"
      destination = "/tmp/slurm-crusoe-startup.sh"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "slurm-crusoe-shutdown.sh"
      destination = "/tmp/slurm-crusoe-shutdown.sh"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "slurm.conf"
      destination = "/tmp/slurm.conf"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "enroot/enroot.conf"
      destination = "/tmp/enroot.conf"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "monitoring/telegraf.conf"
      destination = "/tmp/telegraf.conf"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "monitoring/prometheus.yml"
      destination = "/tmp/prometheus.yml"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "file" {
      source      = "monitoring/targets-prom.py"
      destination = "/tmp/targets-prom.py"
      connection {
        type = "ssh"
        user = "root"
        host = "${self.network_interfaces[0].public_ipv4.address}"
        private_key = file("${local.my_ssh_privkey_path}")
      }
    }
    provisioner "local-exec" {
        command = "rm -rf /tmp/metadata.${self.name}.json"
    }
}

resource "crusoe_vpc_firewall_rule" "grafana_rule" {
  network           = crusoe_compute_instance.headnode_vm1.network_interfaces[0].network
  name              = "grafana-access"
  action            = "allow"
  direction         = "ingress"
  protocols         = "tcp"
  source            = "0.0.0.0/0"
  source_ports      = "1-65535"
  destination       = crusoe_compute_instance.headnode_vm1.network_interfaces[0].public_ipv4.address
  destination_ports = "3000"
}
