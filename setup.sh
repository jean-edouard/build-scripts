#!/bin/bash -e

DUDE="openxt"

if [ $# -ne 0 ]; then
    if [ $# -ne 2 ] || [ $1 != "-u"]; then
	echo "Usage: ./setup.sh [-u user]"
	exit 1
    fi
    DUDE=$2
fi

# This script sets up the host (just installs packages and adds a user),
# and sets up LXC containers to build OpenXT

apt-get install lxc

# If one of the containers already exist, let's just bail
if [ `lxc-ls | grep ${DUDE}-oe`     ] || \
   [ `lxc-ls | grep ${DUDE}-debian` ] || \
   [ `lxc-ls | grep ${DUDE}-centos` ]; then
    echo "Some containers already exist, can't continue."
    exit 1
fi

# Install packages on the host, all at once to be faster
PKGS=""
#PKGS="$PKGS virtualbox" # Un-comment to setup a Windows VM
PKGS="$PKGS bridge-utils libvirt-bin curl jq git sudo" # lxc and misc
PKGS="$PKGS debootstrap" # Debian container
PKGS="$PKGS librpm3 librpmbuild3 librpmio3 librpmsign1 libsqlite0 python-rpm python-sqlite python-sqlitecachec python-support python-urlgrabber rpm rpm-common rpm2cpio yum debootstrap bridge-utils" # Centos container
apt-get update
# That's a lot of packages, a fetching failure can happen, try twice.
apt-get install $PKGS || apt-get install $PKGS

# Create an openxt user on the host and make it a sudoer
if [ ! `cut -d ":" -f 1 /etc/passwd | grep "^${DUDE}$"` ]; then
    echo "Creating an openxt user for building, please choose a password."
    adduser --gecos "" ${DUDE}
    mkdir -p /home/${DUDE}/.ssh
    touch /home/${DUDE}/.ssh/authorized_keys
    chown -R ${DUDE}:${DUDE} /home/${DUDE}/.ssh
    echo "${DUDE}  ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

# Create an SSH key for the user, to communicate with the containers
if [ ! -d /home/${DUDE}/ssh-key ]; then
    mkdir /home/${DUDE}/ssh-key
    ssh-keygen -N "" -f /home/${DUDE}/ssh-key/openxt
    chown -R ${DUDE}:${DUDE} /home/${DUDE}/ssh-key
fi

# Make up a network range 192.168.(150 + uid % 100).0
# And a MAC range 00:FF:AA:42:(uid % 100):01
DUDE_ID=`id -u ${DUDE}`
IP_C=$(( 150 + ${DUDE_ID} % 100 ))
MAC_E=$(( ${DUDE_ID} % 100 ))

# Setup LXC networking on the host, to give known IPs to the containers
if [ ! -f /etc/libvirt/qemu/networks/${DUDE}.xml ]; then
    cat > /etc/libvirt/qemu/networks/${DUDE}.xml <<EOF
<network>
  <name>${DUDE}</name>
  <bridge name="${DUDE}br0"/>
  <forward/>
  <ip address="192.168.${IP_C}.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.${IP_C}.2" end="192.168.${IP_C}.254"/>
      <host mac="00:FF:AA:42:${MAC_E}:01" name="${DUDE}-oe"     ip="192.168.${IP_C}.101" />
      <host mac="00:FF:AA:42:${MAC_E}:02" name="${DUDE}-debian" ip="192.168.${IP_C}.102" />
      <host mac="00:FF:AA:42:${MAC_E}:03" name="${DUDE}-centos" ip="192.168.${IP_C}.103" />
    </dhcp>
  </ip>
</network>
EOF
    /etc/init.d/libvirtd restart
    virsh net-autostart ${DUDE}
fi
virsh net-start ${DUDE} >/dev/null 2>&1 || true

LXC_PATH=`lxc-config lxc.lxcpath`

# Create a container for the main part of the OpenXT build
echo "Creating    the OpenEmbedded container..."
lxc-create -n ${DUDE}-oe -t debian -- --arch i386 --release squeeze
cat >> ${LXC_PATH}/${DUDE}-oe/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = ${DUDE}br0
lxc.network.hwaddr = 00:FF:AA:42:${MAC_E}:01
lxc.network.ipv4 = 0.0.0.0/24
EOF
echo "Configuring the OpenEmbedded container..."
chroot ${LXC_PATH}/${DUDE}-oe/rootfs /bin/bash -e <<'EOF'
# Remove root password
passwd -d root
# Fix networking
sed -i '/^start)$/a        mkdir -p /dev/shm/network/' /etc/init.d/networking
PKGS=""
PKGS="$PKGS openssh-server openssl"
PKGS="$PKGS sed wget cvs subversion git-core coreutils unzip texi2html texinfo docbook-utils gawk python-pysqlite2 diffstat help2man make gcc build-essential g++ desktop-file-utils chrpath cpio" # OE main deps
PKGS="$PKGS ghc guilt iasl quilt bin86 bcc libsdl1.2-dev liburi-perl genisoimage policycoreutils unzip" # OpenXT-specific deps
apt-get update
# That's a lot of packages, a fetching failure can happen, try twice.
apt-get -y install $PKGS </dev/null || apt-get -y install $PKGS </dev/null

# Use bash instead of dash for /bin/sh
mkdir -p /tmp
echo "dash dash/sh boolean false" > /tmp/preseed.txt
debconf-set-selections /tmp/preseed.txt
dpkg-reconfigure -f noninteractive dash

# Hack: Make uname report a 32bits kernel
mv /bin/uname /bin/uname.real
echo '#!/bin/bash' > /bin/uname
echo '/bin/uname.real $@ | sed "s/amd64/i686/g" | sed "s/x86_64/i686/g"' >> /bin/uname
chmod +x /bin/uname

# Add a build user
adduser --disabled-password --gecos "" build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-oe -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh

# Create build certs
mkdir /home/build/certs
openssl genrsa -out /home/build/certs/prod-cakey.pem 2048
openssl genrsa -out /home/build/certs/dev-cakey.pem 2048
openssl req -new -x509 -key /home/build/certs/prod-cakey.pem -out /home/build/certs/prod-cacert.pem -days 1095 -subj "/C=US/ST=Massachusetts/L=Boston/O=OpenXT/OU=OpenXT/CN=openxt.org"
openssl req -new -x509 -key /home/build/certs/dev-cakey.pem -out /home/build/certs/dev-cacert.pem -days 1095 -subj "/C=US/ST=Massachusetts/L=Boston/O=OpenXT/OU=OpenXT/CN=openxt.org"
chown -R build:build /home/build/certs
EOF
# Allow the host to SSH to the container
cat /home/${DUDE}/ssh-key/openxt.pub >> ${LXC_PATH}/${DUDE}-oe/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat ${LXC_PATH}/${DUDE}-oe/rootfs/home/build/.ssh/id_dsa.pub >> /home/${DUDE}/.ssh/authorized_keys
ssh-keyscan -H 192.168.${IP_C}.1 >> ${LXC_PATH}/${DUDE}-oe/rootfs/home/build/.ssh/known_hosts

# Create a container for the Debian tool packages for OpenXT
echo "Creating    the Debian container..."
lxc-create -n ${DUDE}-debian -t debian -- --arch amd64 --release jessie
cat >> ${LXC_PATH}/${DUDE}-debian/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = ${DUDE}br0
lxc.network.hwaddr = 00:FF:AA:42:${MAC_E}:02
EOF
echo "Configuring the Debian container..."
chroot ${LXC_PATH}/${DUDE}-debian/rootfs /bin/bash -e <<'EOF'
passwd -d root
PKGS=""
PKGS="$PKGS openssh-server openssl git"
PKGS="$PKGS schroot sbuild reprepro" # Debian package building deps
apt-get update
apt-get -y install $PKGS </dev/null

# Add a build user
adduser --disabled-password --gecos "" build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-debian -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh
EOF
# Allow the host to SSH to the container
cat /home/${DUDE}/ssh-key/openxt.pub >> ${LXC_PATH}/${DUDE}-debian/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat ${LXC_PATH}/${DUDE}-debian/rootfs/home/build/.ssh/id_dsa.pub >> /home/${DUDE}/.ssh/authorized_keys
ssh-keyscan -H 192.168.${IP_C}.1 >> ${LXC_PATH}/${DUDE}-debian/rootfs/home/build/.ssh/known_hosts

# Create a container for the Centos tool packages for OpenXT
echo "Creating    the Centos container..."
lxc-create -n ${DUDE}-centos -t centos
cat >> ${LXC_PATH}/${DUDE}-centos/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = ${DUDE}br0
lxc.network.hwaddr = 00:FF:AA:42:${MAC_E}:03
EOF
echo "Configuring the Centos container..."
chroot ${LXC_PATH}/${DUDE}-centos/rootfs /bin/bash -e <<'EOF'
passwd -d root

# Add a build user
adduser build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-centos -f /home/build/.ssh/id_dsa
chown -R build:build /home/build/.ssh
EOF
# Allow the host to SSH to the container
cat /home/${DUDE}/ssh-key/openxt.pub >> ${LXC_PATH}/${DUDE}-centos/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat ${LXC_PATH}/${DUDE}-centos/rootfs/home/build/.ssh/id_dsa.pub >> /home/${DUDE}/.ssh/authorized_keys
ssh-keyscan -H 192.168.${IP_C}.1 >> ${LXC_PATH}/${DUDE}-centos/rootfs/home/build/.ssh/known_hosts

# Setup a mirror of the git repositories, for the build to be consistant (and slightly faster)
if [ ! -d /home/git ]; then
    mkdir /home/git
    chown nobody:nogroup /home/git
    chmod 777 /home/git
fi
if [ ! -d /home/git/${DUDE} ]; then
    mkdir -p /home/git/${DUDE}
    cd /home/git/${DUDE}
    for repo in `curl -s "https://api.github.com/orgs/OpenXT/repos?per_page=100" | jq '.[].name' | cut -d '"' -f 2 | sort -u`; do
	git clone --mirror https://github.com/OpenXT/${repo}.git
    done
    cd - > /dev/null
    chown -R ${DUDE}:${DUDE} /home/git/${DUDE}
fi

cp build.sh /home/${DUDE}
chown ${DUDE}:${DUDE} /home/${DUDE}/build.sh
echo "Done! Now login as ${DUDE} and run ./build.sh to start a build."
