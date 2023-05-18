# Creating Autoscaled-enabled SLURM Cluster on Crusoe

This is a reference design implementation of [SLURM](https://slurm.schedmd.com/overview.html) on Crusoe Cloud. This implementation has support for multiple paritions and specific nodegroups within those partitions. The cluster also has support to a cluster autoscaler that will provision instances on Crusoe based on demand on the cluster. The terraform script `main.tf` is the main entry point which will just provision the headnode and using the SLURM Power Plugin will start additional compute nodes based on jobs submitted to the headnode.

## Known Issues
1. Currently we only have GPU-enabled instances, the headnode of the cluster is based on a single GPU to lower costs. This will be replaced with CPU-based instances once available

## Deployment
Step 1. Install Terraform
On your client machine where you deploy the headnode of the cluster install Terraform following the instructions [here](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli).

Step 2. Install the Crusoe Cloud CLI
Install the Crusoe Cloud ClI following [these instructions](https://docs.crusoecloud.com/quickstart/install-the-cli/index.html), setup the authentication layer by creating ssh keys and API tokens.
