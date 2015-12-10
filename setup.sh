#!/bin/bash -e

if [ `lxc-ls | grep openxt-oe`     ] || \
   [ `lxc-ls | grep openxt-debian` ] || \
   [ `lxc-ls | grep openxt-centos` ]; then
    echo "Some containers already exist, can't continue."
    exit 1
fi

PKGS=""
PKGS="$PKGS lxc virtualbox bridge-utils libvirt-bin curl jq git" # VirtualBox, lxc and misc
PKGS="$PKGS debootstrap" # Debian container
PKGS="$PKGS librpm3 librpmbuild3 librpmio3 librpmsign1 libsqlite0 python-rpm python-sqlite python-sqlitecachec python-support python-urlgrabber rpm rpm-common rpm2cpio yum debootstrap bridge-utils" # Centos container

apt-get update
apt-get install $PKGS

if [ ! `cut -d ':' -f 1 /etc/passwd | grep '^openxt$'` ]; then
    echo "Creating an openxt user for building, please choose a password."
    adduser --gecos "" openxt
fi

if [ ! -d /home/openxt/ssh-key ]; then
    mkdir /home/openxt/ssh-key
    ssh-keygen -N "" -f /home/openxt/ssh-key/openxt
    chown -R openxt:openxt /home/openxt/ssh-key/openxt
fi

# Setup networking
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
    </dhcp>
  </ip>
</network>
EOF
    /etc/init.d/libvirtd restart
    virsh net-autostart openxt
fi
virsh net-start openxt >/dev/null 2>&1 || true

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
sed -i '/start)/a        mkdir -p /dev/shm/network/' /etc/init.d/networking
PKGS=""
PKGS="$PKGS openssh-server openssl"
#PKGS="$PKGS sed wget cvs subversion git-core coreutils unzip texi2html texinfo docbook-utils gawk python-pysqlite2 diffstat help2man make gcc build-essential g++ desktop-file-utils chrpath" # OE main deps
#PKGS="$PKGS ghc guilt iasl quilt bin86 bcc libsdl1.2-dev liburi-perl genisoimage policycoreutils unzip" # OpenXT-specific deps
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

adduser --disabled-password --gecos "" build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
chown -R build:build /home/build/.ssh

mkdir /home/build/certs
openssl genrsa -out /home/build/certs/prod-cakey.pem 2048
openssl genrsa -out /home/build/certs/dev-cakey.pem 2048
openssl req -new -x509 -key /home/build/certs/prod-cakey.pem -out /home/build/certs/prod-cacert.pem -days 1095 -subj "/C=US/ST=Massachusetts/L=Boston/O=OpenXT/OU=OpenXT/CN=openxt.org"
openssl req -new -x509 -key /home/build/certs/dev-cakey.pem -out /home/build/certs/dev-cacert.pem -days 1095 -subj "/C=US/ST=Massachusetts/L=Boston/O=OpenXT/OU=OpenXT/CN=openxt.org"
chown -R build:build /home/build/certs
EOF
cat /home/openxt/ssh-key/openxt.pub >> /var/lib/lxc/openxt-oe/rootfs/home/build/.ssh/authorized_keys

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
# TODO: setup networking
PKGS=""
PKGS="$PKGS openssh-server openssl"
#PKGS="$PKGS schroot sbuild reprepro" # Debian package building deps
apt-get update
apt-get -y install $PKGS </dev/null

adduser --disabled-password --gecos "" build
mkdir -p /home/build/.ssh
touch /home/build/.ssh/authorized_keys
chown -R build:build /home/build/.ssh
EOF
cat /home/openxt/ssh-key/openxt.pub >> /var/lib/lxc/openxt-debian/rootfs/home/build/.ssh/authorized_keys

if [ ! -d /home/openxt/git ]; then
    mkdir /home/openxt/git
    cd /home/openxt/git
    for repo in `curl -s "https://api.github.com/orgs/OpenXT/repos?per_page=100" | jq '.[].name' | cut -d '"' -f 2 | sort -u`; do
	git clone --mirror https://github.com/OpenXT/${repo}.git
    done
    cd - > /dev/null
    chown -R openxt:openxt /home/openxt/git
fi
