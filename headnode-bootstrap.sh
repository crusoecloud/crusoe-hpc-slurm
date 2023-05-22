#!/bin/bash

# adding packages
export DEBIAN_FRONTEND=noninteractive
echo "deb [trusted=yes] https://apt.fury.io/crusoe/ * *" > /etc/apt/sources.list.d/fury.list

apt update && apt upgrade -y
apt install -y jq preload nvme-cli mdadm nfs-common nfs-kernel-server munge libmunge-dev crusoe ntp
sudo systemctl enable --now ntp
# mounting any detected local nvme drives
num_nvme=`nvme list | grep -i /dev | wc -l`

if [[ $num_nvme -eq 1 ]]; then
   dev_name=`nvme list | grep -i /dev | awk '{print $1}'`
   mkfs.ext4 $dev_name
   mkdir /nvme && mount -t ext4 /dev/nvme0n1 /nvme
elif [[ $num_nvme -gt 1 ]]; then
   dev_name=`nvme list | grep -i /dev | awk '{print $1}'`
   mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$num_nvme $dev_name
   mkfs.ext4 /dev/md0
   mkdir /raid0 && mount -t ext4 /dev/md0 /raid0
else
   echo "no ephemeral drives detected"
fi

# setting hostname
local_ip=`jq ".network_interfaces[0].ips[0].private_ipv4.address" /root/metadata.json | tr -d '"'`
host=`jq ".name" /root/metadata.json | tr -d '"'`
/usr/bin/hostname $host

# setup local nfs for slurm
mkdir -p /nfs
echo "/nfs 172.27.0.0/16(rw,async,no_subtree_check,no_root_squash)" | tee /etc/exports
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -av

#Setup Munge
echo "welcometoslurmcrusoeuserwelcometoslurmcrusoeuserwelcometoslurmcrusoeuser" | sudo tee /etc/munge/munge.key
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 600 /etc/munge/munge.key
sudo chown -R munge /etc/munge/ /var/log/munge/
sudo chmod 0700 /etc/munge/ /var/log/munge/
sudo systemctl enable --now munge

#SLURM headnode download extract install
export SLURM_HOME=/nfs/slurm
wget -O /tmp/slurm.tar.bz2 "https://download.schedmd.com/slurm/slurm-23.02.2.tar.bz2"
tar -xvf /tmp/slurm.tar.bz2 -C /tmp
/tmp/slurm-*/configure --prefix=$SLURM_HOME && make -j $(nproc) && make install
mv /tmp/slurm-*/etc $SLURM_HOME
mv /tmp/slurm.conf $SLURM_HOME/etc

cp /etc/slurmd.service /usr/lib/systemd/system
cp /etc/slurmd.service $SLURM_HOME/etc/
cp /etc/slurmctld.service /usr/lib/systemd/system
cp /etc/slurmctld.service $SLURM_HOME/etc/

sed -i "s|@HEADNODE@|$host|g" $SLURM_HOME/etc/slurm.conf
sed -i "s|@IP@|$local_ip|g" $SLURM_HOME/etc/slurm.conf
sed -i "s|@EXC@|$host|g" $SLURM_HOME/etc/slurm.conf

echo 'SLURM_HOME=/nfs/slurm' | sudo tee /etc/profile.d/slurm.sh
echo 'SLURM_CONF=$SLURM_HOME/slurm.conf' | sudo tee -a /etc/profile.d/slurm.sh
echo 'PATH=$SLURM_HOME/bin:$PATH' | sudo tee -a /etc/profile.d/slurm.sh
 
mkdir -p /var/spool/slurm
mkdir -p $SLURM_HOME/etc/slurm.conf.d

# Configure SLURM nodes
echo "NodeName=@RANGE@ CPUs=8 State=Cloud" | sudo tee $SLURM_HOME/etc/slurm.conf.d/slurm_nodes.conf
sed -i "s|@RANGE@|$host|g" $SLURM_HOME/etc/slurm.conf.d/slurm_nodes.conf
echo "NodeName=aragab-compute-[0-20] CPUs=8 State=Cloud" | sudo tee -a $SLURM_HOME/etc/slurm.conf.d/slurm_nodes.conf

# Put Startup/Shutdown scripts in place
mv /tmp/slurm-crusoe-shutdown.sh $SLURM_HOME/bin && chmod +x $SLURM_HOME/bin/slurm-crusoe-shutdown.sh
mv /tmp/slurm-crusoe-startup.sh $SLURM_HOME/bin && chmod +x $SLURM_HOME/bin/slurm-crusoe-startup.sh
touch $SLURM_HOME/etc/gres.conf
# set execute bit on crusoe binary
mkdir -p /nfs/crusoecloud
chmod +x /root/crusoe && mv /root/crusoe /nfs/crusoecloud
cp /etc/profile.d/crusoe-cli.sh /nfs/crusoecloud

DEBIAN_FRONTEND=noninteractive apt install -y jq squashfs-tools parallel fuse-overlayfs libnvidia-container-tools pigz \
                                              squashfuse devscripts debhelper zstd libslurm-dev

# Install Enroot
arch=$(dpkg --print-architecture)
wget -O /tmp/enroot.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot_3.4.1-1_${arch}.deb"
wget -O /tmp/enroot_caps.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot+caps_3.4.1-1_${arch}.deb"
sudo apt install -y /tmp/enroot*.deb

# Symlink Scratch to local ephemeral drive(s)
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

# Install NVIDIA Pyxis
git clone https://github.com/NVIDIA/pyxis.git /tmp/pyxis
cd /tmp/pyxis
CFLAGS="-I /nfs/slurm/include" make orig
CFLAGS="-I /nfs/slurm/include" make deb
dpkg -i ../nvslurm-plugin-pyxis_*_amd64.deb

# Configure Enroot/Pyxis
mkdir -p /nfs/slurm/etc/plugstack.conf.d
echo -e 'include /nfs/slurm/etc/plugstack.conf.d/*' | sudo tee /nfs/slurm/etc/plugstack.conf
ln -s -f /usr/share/pyxis/pyxis.conf /nfs/slurm/etc/plugstack.conf.d/pyxis.conf
mv /tmp/enroot.conf /etc/enroot/enroot.conf
cp /etc/enroot/enroot.conf /nfs/enroot.conf

# Configure monitoring
mkdir -p /nfs/monitoring


wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
wget -q https://repos.influxdata.com/influxdata-archive_compat.key
echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list

apt update && apt install -y telegraf prometheus grafana

mv /tmp/telegraf.conf /etc/telegraf/telegraf.conf
sed -i "s|@HEADNODE_IP@|$local_ip|g" /etc/telegraf/telegraf.conf
cp /etc/telegraf/telegraf.conf /nfs/monitoring/telegraf.conf

mv /tmp/prometheus.yml /etc/prometheus/prometheus.yml
sed -i "s|@HEADNODE_IP@|$local_ip|g" /etc/prometheus/prometheus.yml

#Start services
sudo systemctl enable --now prometheus
sudo systemctl enable --now telegraf
sudo systemctl enable --now grafana-server
sudo systemctl enable --now slurmctld
sudo systemctl enable --now slurmd