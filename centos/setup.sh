#!/bin/sh

# Remove the root password
passwd -d root

# Install required packages
yum install rpm-build which sudo git which
wget http://pkgs.repoforge.org/dkms/dkms-2.1.1.2-1.el6.rf.noarch.rpm
rpm -ivh dkms-2.1.1.2-1.el6.rf.noarch.rpm

# Add a build user
adduser build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-centos -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh

# Make the user a passwordless sudoer, as dkms unfortunately needs to run as root
echo "build   ALL=(ALL)       NOPASSWD:ALL" >> /etc/sudoers
