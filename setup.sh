#!/bin/bash -e

# This script sets up the host (just installs packages and adds a user),
# and sets up LXC containers to build OpenXT

apt-get install lxc

# If one of the containers already exist, let's just bail
if [ `lxc-ls | grep openxt-oe`     ] || \
   [ `lxc-ls | grep openxt-debian` ] || \
   [ `lxc-ls | grep openxt-centos` ]; then
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
apt-get install $PKGS

# Create an openxt user on the host and make it a sudoer
if [ ! `cut -d ':' -f 1 /etc/passwd | grep '^openxt$'` ]; then
    echo "Creating an openxt user for building, please choose a password."
    adduser --gecos "" openxt
    mkdir -p /home/openxt/.ssh
    touch /home/openxt/.ssh/authorized_keys
    chown -R openxt:openxt /home/openxt/.ssh
    echo 'openxt  ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi

# Create an SSH key for the user, to communicate with the containers
if [ ! -d /home/openxt/ssh-key ]; then
    mkdir /home/openxt/ssh-key
    ssh-keygen -N "" -f /home/openxt/ssh-key/openxt
    chown -R openxt:openxt /home/openxt/ssh-key/openxt
fi

# Setup LXC networking on the host, to give known IPs to the containers
if [ ! -f /etc/libvirt/qemu/networks/openxt.xml ]; then
    cat > /etc/libvirt/qemu/networks/openxt.xml <<EOF
<network>
  <name>openxt</name>
  <bridge name="oxtbr0"/>
  <forward/>
  <ip address="192.168.123.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.123.2" end="192.168.123.254"/>
      <host mac="00:FF:AA:42:42:01" name="openxt-oe"     ip="192.168.123.101" />
      <host mac="00:FF:AA:42:42:02" name="openxt-debian" ip="192.168.123.102" />
      <host mac="00:FF:AA:42:42:03" name="openxt-centos" ip="192.168.123.103" />
    </dhcp>
  </ip>
</network>
EOF
    /etc/init.d/libvirtd restart
    virsh net-autostart openxt
fi
virsh net-start openxt >/dev/null 2>&1 || true

# Create a container for the main part of the OpenXT build
echo "Creating    the OpenEmbedded container..."
lxc-create -n openxt-oe -t debian -- --arch i386 --release squeeze
cat >> /var/lib/lxc/openxt-oe/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = oxtbr0
lxc.network.hwaddr = 00:FF:AA:42:42:01
lxc.network.ipv4 = 0.0.0.0/24
EOF
echo "Configuring the OpenEmbedded container..."
chroot /var/lib/lxc/openxt-oe/rootfs /bin/bash -e <<'EOF'
# Remove root password
passwd -d root
# Fix networking
sed -i '/^start)$/a        mkdir -p /dev/shm/network/' /etc/init.d/networking
PKGS=""
PKGS="$PKGS openssh-server openssl"
PKGS="$PKGS sed wget cvs subversion git-core coreutils unzip texi2html texinfo docbook-utils gawk python-pysqlite2 diffstat help2man make gcc build-essential g++ desktop-file-utils chrpath cpio" # OE main deps
PKGS="$PKGS ghc guilt iasl quilt bin86 bcc libsdl1.2-dev liburi-perl genisoimage policycoreutils unzip" # OpenXT-specific deps
apt-get update
apt-get -y install $PKGS </dev/null

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
ssh-keyscan -H 192.168.123.1 >> /home/build/.ssh/known_hosts
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
cat /home/openxt/ssh-key/openxt.pub >> /var/lib/lxc/openxt-oe/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat /var/lib/lxc/openxt-oe/rootfs/home/build/.ssh/id_dsa.pub >> /home/openxt/.ssh/authorized_keys

# Create a container for the Debian tool packages for OpenXT
echo "Creating    the Debian container..."
lxc-create -n openxt-debian -t debian -- --arch amd64 --release jessie
cat >> /var/lib/lxc/openxt-debian/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = oxtbr0
lxc.network.hwaddr = 00:FF:AA:42:42:02
EOF
echo "Configuring the Debian container..."
chroot /var/lib/lxc/openxt-debian/rootfs /bin/bash -e <<'EOF'
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
ssh-keyscan -H 192.168.123.1 >> /home/build/.ssh/known_hosts
chown -R build:build /home/build/.ssh
EOF
# Allow the host to SSH to the container
cat /home/openxt/ssh-key/openxt.pub >> /var/lib/lxc/openxt-debian/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat /var/lib/lxc/openxt-debian/rootfs/home/build/.ssh/id_dsa.pub >> /home/openxt/.ssh/authorized_keys

# Create a container for the Centos tool packages for OpenXT
echo "Creating    the Centos container..."
lxc-create -n openxt-centos -t centos
cat >> /var/lib/lxc/openxt-centos/config <<EOF
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = oxtbr0
lxc.network.hwaddr = 00:FF:AA:42:42:03
EOF
echo "Configuring the Centos container..."
chroot /var/lib/lxc/openxt-centos/rootfs /bin/bash -e <<'EOF'
passwd -d root

# Add a build user
adduser build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
ssh-keygen -N "" -t dsa -C build@openxt-centos -f /home/build/.ssh/id_dsa
ssh-keyscan -H 192.168.123.1 >> /home/build/.ssh/known_hosts
chown -R build:build /home/build/.ssh
EOF
# Allow the host to SSH to the container
cat /home/openxt/ssh-key/openxt.pub >> /var/lib/lxc/openxt-centos/rootfs/home/build/.ssh/authorized_keys
# Allow the container to SSH to the host
cat /var/lib/lxc/openxt-centos/rootfs/home/build/.ssh/id_dsa.pub >> /home/openxt/.ssh/authorized_keys

# Setup a mirror of the git repositories, for the build to be consistant (and slightly faster)
if [ ! -d /home/openxt/git ]; then
    mkdir /home/openxt/git
    cd /home/openxt/git
    for repo in `curl -s "https://api.github.com/orgs/OpenXT/repos?per_page=100" | jq '.[].name' | cut -d '"' -f 2 | sort -u`; do
	git clone --mirror https://github.com/OpenXT/${repo}.git
    done
    cd - > /dev/null
    chown -R openxt:openxt /home/openxt/git
fi

cp build.sh /home/openxt
chown openxt:openxt /home/openxt/build.sh
echo "Done! Now login as openxt and run ./build.sh to start a build."
