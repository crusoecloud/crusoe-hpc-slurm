# Creating Autoscaled-enabled SLURM Cluster on Crusoe

This is a reference design implementation of [SLURM](https://slurm.schedmd.com/overview.html) on Crusoe Cloud. This implementation has support for multiple paritions and specific nodegroups within those partitions. The cluster also has support to a cluster autoscaler that will provision instances on Crusoe based on demand on the cluster. Finally we have include support for NVIDIA [enroot](https://github.com/NVIDIA/enroot) and [pyxis](https://github.com/NVIDIA/pyxis). Which allows you to run distributed workloads with native container support. The terraform script `main.tf` is the main entry point which will just provision the headnode and using the SLURM Power Plugin will start additional compute nodes based on jobs submitted to the headnode.

## Known Issues
1. Currently we only have GPU-enabled instances, the headnode of the cluster is based on a single GPU to lower costs. This will be replaced with CPU-based instances once available

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
Step 4. In the `main.tf` file 

