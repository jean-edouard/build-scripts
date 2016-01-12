#!/bin/sh

# Remove the root password
passwd -d root

# Install required packages
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install rpm-build createrepo which sudo git which wget gcc kernel-devel tar dkms

# Add a build user
adduser build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-centos -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh

# Make the user a passwordless sudoer, as dkms unfortunately needs to run as root
echo "build   ALL=(ALL)       NOPASSWD:ALL" >> /etc/sudoers
