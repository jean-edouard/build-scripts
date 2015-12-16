# Setup sbuild
apt-get install sbuild build-essential dh-make dkms
mkdir /root/.gnupg
sbuild-update --keygen
sbuild-adduser build
sbuild-createchroot wheezy /home/chroots/wheezy-i386 http://httpredir.debian.org/debian --arch i386
sbuild-createchroot wheezy /home/chroots/wheezy-amd64 http://httpredir.debian.org/debian --arch amd64
sbuild-createchroot jessie /home/chroots/jessie-i386 http://httpredir.debian.org/debian --arch i386
sbuild-createchroot jessie /home/chroots/jessie-amd64 http://httpredir.debian.org/debian --arch amd64

# Build
su - build <<EOF
git clone -b sbuild https://github.com/jean-edouard/pv-linux-drivers.git
mkdir -p wheezy
cd wheezy
sbuild --dist=wheezy --arch-all ../pv-linux-drivers/xenmou
cd - >/dev/null
mkdir -p jessie
cd jessie
sbuild --dist=jessie --arch-all ../pv-linux-drivers/xenmou
cd - >/dev/null
EOF
