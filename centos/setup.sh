#!/bin/sh

# Remove the root password
passwd -d root

# Install required packages
# The following line must be done first,
#  it will make the next yum command use the correct packages
yum -y install centos-release-xen
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install rpm-build createrepo which sudo git which wget gcc make kernel-devel tar dkms

# Setup symlinks to make dkms happy
for kernelpath in `ls /usr/src/*`; do
    kernel=`basename $kernelpath`
    mkdir -p /lib/modules/${kernel}
    [ -e /lib/modules/${kernel}/build ] || ln -s ${kernelpath} /lib/modules/${kernel}/build
    [ -e /lib/modules/${kernel}/source ] || ln -s ${kernelpath} /lib/modules/${kernel}/source
done

# Add a build user
adduser build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-centos -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh

# Make the user a passwordless sudoer, as dkms unfortunately needs to run as root
echo "build   ALL=(ALL)       NOPASSWD:ALL" >> /etc/sudoers
