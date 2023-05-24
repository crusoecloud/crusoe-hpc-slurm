# Create an Autoscaled-enabled SLURM Cluster on Crusoe

This is a reference design implementation of [SLURM](https://slurm.schedmd.com/overview.html) on Crusoe Cloud. This implementation has support for multiple paritions and specific nodegroups within those partitions. The cluster also has support to a cluster autoscaler that will provision instances on Crusoe based on demand on the cluster. The terraform script `main.tf` is the main entry point which will just provision the headnode and using the SLURM Power Plugin will start additional compute nodes based on jobs submitted to the headnode.

## Known Issues
1. Currently we only have GPU-enabled instances, the headnode of the cluster is based on a single GPU to lower costs. This will be replaced with CPU-based instances once available

## Description of the Architecture
The terraform script will simply provision a headnode, the `headnode-bootstrap.sh`script will perform the following:
1. Will scan for number of ephemeral drives and mount it as RAID0 for number of drives > 1 at mount point `/raid0` for instances with a single nvme local epehmeral drive it will be mounted as `/nvme` and the `scratch` directory will inside that path
2. A NFS server is also setup at `/nfs/slurm` which provides the SLURM binaries, libraries and helper code to the ephemeral compute nodes
3. Download and install SLURM source tree. The SLURM version is controlled by the bootstrap script to ensure its supported on Crusoe. Changing the version in the repo is NOT supported, unless is validated by Crusoe.

## Support for NVIDIA Enroot/Pyxis
Included in the deployment is support for (enroot)[https://github.com/NVIDIA/enroot] and pyxis. Purpose built to support native container orchestration within SLURM to run container images across the cluster.
All enroot images are on the `/scratch` directory of each node in the cluster. Adding credentials to access various registries can be done by editing a `$HOME/enroot/.credentials` file.

## Monitoring
![heatmap](/imgs/heatmap.png)
The headnode is hosting a Telegraf-Prometheus-Grafana(TPG)-stack, and each worker runs Telegraf and creates a `/metrics` endpoint from which the 
headnode Prometheus will poll. 
![metrics](/imgs/metrics.png)

## Deployment
Step 1. Install Terraform
On your client machine where you deploy the headnode of the cluster install Terraform following the instructions [here](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli).

Step 2. Install the Crusoe Cloud CLI
Install the Crusoe Cloud ClI following [these instructions](https://docs.crusoecloud.com/quickstart/install-the-cli/index.html), setup the authentication layer by creating ssh keys and API tokens.

Step 3. Clone repo and create a `variables.tf` File
```
git clone https://github.com/crusoecloud/crusoe-hpc-slurm.git
cd crusoe-hpc-slurm
```
Your `variables.tf` contains the following:
```
variable "access_key" {
   description = "Crusoe API Access Key"
   type        = string
   default     = "<ACCESS_KEY>"
 }
variable "secret_key" {
   description = "Crusoe API Secret Key"
   type        = string
   default     = "<SECRET_KEY>"
 }
```
Step 4. In the `main.tf` file replace the local values with provide a path for the private ssh key and the string of the public key. And choose an instance type for the headnode
```
locals {
  my_ssh_privkey_path="/Users/amrragab/.ssh/id_ed25519"
  my_ssh_pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdc3Aaj8RP7ru1oSxUuehTRkpYfvxTxpvyJEZqlqyze amrragab@MBP-Amr-Ragab.local"
  headnode_instance_type="a100-80gb.1x"
}
``` 
Step 5. Execute the terraform script
```
terraform init
terraform plan
terraform apply
```
