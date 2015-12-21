#!/bin/sh

# Remove xenmou
sudo dkms remove -m xenmou -v 1.0 --all || true
sudo rm -rf /usr/src/xenmou-1.0
rm -rf pv-linux-drivers

# Fetch xenmou
git clone -b sbuild https://github.com/jean-edouard/pv-linux-drivers.git
sudo cp -r pv-linux-drivers/xenmou/ /usr/src/xenmou-1.0

# Build xenmou
sudo dkms add -m xenmou -v 1.0
sudo dkms build -m xenmou -v 1.0 -k 2.6.32-573.12.1.el6.x86_64 --kernelsourcedir=/usr/src/kernels/2.6.32-573.12.1.el6.x86_64
sudo dkms mkrpm -m xenmou -v 1.0 -k 2.6.32-573.12.1.el6.x86_64
