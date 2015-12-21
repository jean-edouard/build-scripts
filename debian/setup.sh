#!/bin/sh

MIRROR=%MIRROR%

# Remove the root password
passwd -d root

# Install required packages
PKGS=""
PKGS="$PKGS openssh-server openssl git"
PKGS="$PKGS schroot sbuild reprepro build-essential dh-make dkms" # Debian package building deps
apt-get update
apt-get -y install $PKGS </dev/null

# Add a build user
adduser --disabled-password --gecos "" build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-debian -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh

# Setup sbuild
mkdir /root/.gnupg
sbuild-update --keygen
sbuild-adduser build
sbuild-createchroot wheezy /home/chroots/wheezy-i386 $MIRROR --arch i386
sbuild-createchroot wheezy /home/chroots/wheezy-amd64 $MIRROR --arch amd64
sbuild-createchroot jessie /home/chroots/jessie-i386 $MIRROR --arch i386
sbuild-createchroot jessie /home/chroots/jessie-amd64 $MIRROR --arch amd64
