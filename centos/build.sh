#!/bin/sh

set -e

DUDE=%DUDE%
BUILD_DIR=%BUILD_DIR%
IP_C=%IP_C%

mkdir -p $BUILD_DIR/repo/RPMS
cd $BUILD_DIR

KERNEL_VERSION=`ls /lib/modules | tail -1`

rm -rf pv-linux-drivers
git clone -b sbuild2 https://github.com/jean-edouard/pv-linux-drivers.git

for i in `ls -d pv-linux-drivers/openxt-*`; do
    tool=`basename $i`

    # Remove package
    sudo dkms remove -m ${tool} -v 1.0 --all || true
    sudo rm -rf /usr/src/${tool}-1.0

    # Fetch package
    sudo cp -r pv-linux-drivers/${tool} /usr/src/${tool}-1.0

    # Build package
    sudo dkms add -m ${tool} -v 1.0
    sudo dkms build -m ${tool} -v 1.0 -k ${KERNEL_VERSION} --kernelsourcedir=/usr/src/kernels/${KERNEL_VERSION}
    sudo dkms mkrpm -m xenmou -v 1.0 -k ${KERNEL_VERSION}
    cp /var/lib/dkms/${tool}/1.0/rpm/* repo/RPMS
done

# Create the repo
createrepo repo

# Copy the resulting repository
scp -r repo ${DUDE}@192.168.${IP_C}.1:${BUILD_DIR}/rpms

# The script may run in an "ssh -t -t" environment, that won't exit on its own
set +e
exit
