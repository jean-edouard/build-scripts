# Setup sbuild
apt-get install sbuild build-essential dh-make dkms

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
