#!/bin/bash

DEBIAN_FRONTEND=noninteractive apt install -y jq squashfs-tools parallel fuse-overlayfs libnvidia-container-tools pigz \
                                              squashfuse devscripts debhelper zstd libslurm-dev

arch=$(dpkg --print-architecture)
wget -O /tmp/enroot.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot_3.4.1-1_${arch}.deb"
wget -O /tmp/enroot_caps.deb "https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot+caps_3.4.1-1_${arch}.deb"
sudo apt install -y /tmp/enroot*.deb

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

mkdir -p /nfs/slurm/etc/plugstack.conf.d
echo -e 'include /nfs/slurm/etc/plugstack.conf.d/*' | sudo tee /nfs/slurm/etc/plugstack.conf
ln -s -f /usr/share/pyxis/pyxis.conf /nfs/slurm/etc/plugstack.conf.d/pyxis.conf
