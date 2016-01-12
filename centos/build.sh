#!/bin/sh

set -e

DUDE=%DUDE%
BUILD_DIR=%BUILD_DIR%
IP_C=%IP_C%

mkdir -p $BUILD_DIR/repo/RPMS
cd $BUILD_DIR

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
cp /var/lib/dkms/openxt-xenmou/1.0/rpm/* repo/RPMS

# Create the repo
createrepo repo

# Copy the resulting repository
scp -r repo ${DUDE}@192.168.${IP_C}.1:${BUILD_DIR}/rpms

# The script may run in an "ssh -t -t" environment, that won't exit on its own
set +e
exit
