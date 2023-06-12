#!/bin/bash
# AUTHOR: AMR RAGAB
# DESCRIPTION: SLURM STARTUP
# Script/Code is provided, as is, and with no warranty
export SLURM_HOME=/nfs/slurm
export CRUSOE_HOME=/nfs/crusoecloud
export SLURM_HEADNODE_IP=$(jq ".network_interfaces[0].ips[0].private_ipv4.address" /root/metadata.json | tr -d '"')
export SLURM_HEADNODE_NAME=$(jq ".name" /root/metadata.json | tr -d '"')
export SLURM_POWER_LOG=/var/log/power_save.log
export PATH=$PATH:/usr/bin:/usr/local/bin:/nfs/slurm/bin
. $CRUSOE_HOME/crusoe-cli.sh
##############################################
# DONOT EDIT BELOW THIS LINE
##############################################

function crusoe_startup()
{
    TMPFILE=$(mktemp)
    cat << END > $TMPFILE
#!/bin/bash
# compute node can resolve headnode
# adding packages
export SLURM_HOME=/nfs/slurm
export CRUSOE_HOME=/nfs/crusoecloud
export DEBIAN_FRONTEND=noninteractive
echo "deb [trusted=yes] https://apt.fury.io/crusoe/ * *" > /etc/apt/sources.list.d/fury.list

adduser --disabled-password --shell /bin/bash --gecos "ubuntu" ubuntu
echo 'ubuntu  ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers
usermod -aG docker ubuntu

apt update && apt upgrade -y
apt install -y jq preload nvme-cli mdadm nfs-common nfs-kernel-server munge libmunge-dev crusoe ntp
sudo systemctl enable --now ntp
# mounting nfs server from headnode
sudo mkdir -p /nfs
sudo mount -t nfs $SLURM_HEADNODE_IP:/nfs /nfs
sudo mount -t nfs $SLURM_HEADNODE_IP:/home /home

# mounting any detected local nvme drives
num_nvme=\`nvme list | grep -i /dev | wc -l\`

if [[ \$num_nvme -eq 1 ]]; then
   dev_name=\`nvme list | grep -i /dev | awk '{print \$1}'\`
   mkfs.ext4 \$dev_name
   mkdir /nvme && mount -t ext4 /dev/nvme0n1 /nvme
elif [[ \$num_nvme -gt 1 ]]; then
   dev_name=\`nvme list | grep -i /dev | awk '{print \$1}'\`
   mdadm --create --verbose /dev/md127 --level=0 --raid-devices=\$num_nvme \$dev_name
   mkfs.ext4 /dev/md127
   mkdir /raid0 && mount -t ext4 /dev/md127 /raid0
else
   echo "no ephemeral drives detected"
fi

# setting hostname
cp \$CRUSOE_HOME/crusoe-cli.sh /etc/profile.d/crusoe-cli.sh
. /etc/profile.d/crusoe-cli.sh
crusoe compute vms get $1 -f json >> /root/metadata.json
local_ip=\$(jq ".network_interfaces[0].ips[0].private_ipv4.address" /root/metadata.json | tr -d '"')
host=\$(jq ".name" /root/metadata.json | tr -d '"')
/usr/bin/hostname $1

#Setup Munge
sudo cp \$SLURM_HOME/munge.key /etc/munge/munge.key
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 600 /etc/munge/munge.key
sudo chown -R munge /etc/munge/ /var/log/munge/
sudo chmod 0700 /etc/munge/ /var/log/munge/
sudo systemctl enable --now munge

mkdir -p /var/spool/slurm/d
export SLURM_HOME=/nfs/slurm
cp \$SLURM_HOME/etc/slurmd.service /usr/lib/systemd/system

DEBIAN_FRONTEND=noninteractive apt install -y jq squashfs-tools parallel fuse-overlayfs libnvidia-container-tools pigz \
                                              squashfuse devscripts debhelper zstd libslurm-dev

arch=$(dpkg --print-architecture)
wget -O /tmp/enroot.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot_3.4.1-1_\${arch}.deb"
wget -O /tmp/enroot_caps.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot+caps_3.4.1-1_\${arch}.deb"
apt install -y /tmp/enroot*.deb
cp /nfs/enroot.conf /etc/enroot/enroot.conf

if [ -d "/nvme" ]; then
   mkdir /nvme/scratch
   chmod -R 777 /nvme/scratch
   ln -sfn /nvme/scratch /scratch
elif [ -d "/raid0" ]; then
   mkdir /raid0/scratch
   chmod -R 777 /raid0/scratch
   ln -sfn /raid0/scratch /scratch
else
   mkdir /scratch
fi

git clone https://github.com/NVIDIA/pyxis.git /tmp/pyxis
cd /tmp/pyxis
CFLAGS="-I /nfs/slurm/include" make orig
CFLAGS="-I /nfs/slurm/include" make deb
dpkg -i ../nvslurm-plugin-pyxis_*_amd64.deb
echo "required /usr/lib/x86_64-linux-gnu/slurm/spank_pyxis.so runtime_path=/scratch/pyxis" > /usr/share/pyxis/pyxis.conf

apt install -y apt-transport-https software-properties-common wget

wget -q https://repos.influxdata.com/influxdata-archive_compat.key
echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list

apt update && apt install -y telegraf
cp /nfs/monitoring/telegraf.conf /etc/telegraf/telegraf.conf
systemctl enable --now telegraf
systemctl enable --now slurmd.service
END

    crusoe compute vms create --name $1 --type a100-80gb.1x \
        --startup-script $TMPFILE --keyfile $CRUSOE_SSH_PUBLIC_KEY_FILE >> $SLURM_POWER_LOG 2>&1
    rm -rf $TMPFILE
}

export SLURM_ROOT=/nfs/slurm
echo "Resume invoked $0 $*" >> $SLURM_POWER_LOG
hosts=$($SLURM_ROOT/bin/scontrol show hostnames $1)
num_hosts=$(echo "$hosts" | wc -l)
for host in $hosts; do
   crusoe_startup $host &
done
wait
for host in $hosts; do
   compute_private_ip=$(crusoe compute vms get $host -f json | jq ".network_interfaces[0].ips[0].private_ipv4.address" | tr -d '"')
   echo "$compute_private_ip    $host" | tee -a /etc/hosts
   python3 /nfs/monitoring/targets-prom.py add $host
   $SLURM_ROOT/bin/scontrol update nodename=$host nodeaddr=$compute_private_ip nodehostname=$host
done
