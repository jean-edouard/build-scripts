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

if [ ! `cut -d ':' -f 1 /etc/passwd | grep '^build$'` ]; then
    adduser build
fi

if [ ! -d /home/build/ssh-key ]; then
    mkdir /home/build/ssh-key
    ssh-keygen -N "" -f /home/build/ssh-key/openxt
    chown -R build:build /home/build/ssh-key/openxt
fi

# TODO: setup networking

echo "Creating    the OpenEmbedded container..."
lxc-create -n openxt-oe -t debian -- --arch i386 --release squeeze
echo "Configuring the OpenEmbedded container..."
chroot /var/lib/lxc/openxt-oe/rootfs /bin/bash <<'EOF'
passwd -d root
# TODO: setup networking
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
cat /home/build/ssh-key/openxt.pub >> /var/lib/lxc/openxt-oe/rootfs/home/build/.ssh/authorized_keys

if [ ! -d /home/build/git ]; then
    mkdir /home/build/git
    cd /home/build/git
    for repo in `curl -s "https://api.github.com/orgs/OpenXT/repos?per_page=100" | jq '.[].name' | cut -d '"' -f 2 | sort -u`; do
	git clone --mirror https://github.com/OpenXT/${repo}.git
    done
    cd - > /dev/null
    chown -R build:build /home/build/git
fi
