#!/bin/bash
# AUTHOR: AMR RAGAB
# DESCRIPTION: SLURM SHUTDOWN
# Script/Code is provided, as is, and with no warranty

export SLURM_HOME=/nfs/slurm
export CRUSOE_HOME=/nfs/crusoecloud
export SLURM_CONF=/nfs/slurm/etc/slurm.conf
export SLURM_POWER_LOG=/var/log/power_save.log
export PATH=$PATH:/usr/bin:/usr/local/bin:/nfs/slurm/bin
. /nfs/crusoe-cli.sh

function crusoe_stop()
{
    $CRUSOE_HOME/crusoe compute vms stop $1
}

function crusoe_delete()
{
    $CRUSOE_HOME/crusoe compute vms delete $1  >> $SLURM_POWER_LOG 2>&1
    sed -i "/$1/d" $SLURM_HOME/etc/slurm.conf.d/slurm_nodes.conf
}

echo "`date` Suspend invoked $0 $*" >> $SLURM_POWER_LOG
hosts=$($SLURM_HOME/bin/scontrol show hostnames $1)
num_hosts=$(echo "$hosts" | wc -l)

for host in $hosts; do
   crusoe_stop $host &
done
wait
for host in $hosts; do
   crusoe_delete $host &
   sed -i "/$host/d" /etc/hosts
   $SLURM_HOME/bin/scontrol reconfigure
done
