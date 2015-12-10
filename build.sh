#!/bin/bash -e

# TODO: fetch the git mirror

# Create a build dir
BUILD_DIR=`date +%y%m%d`
mkdir $BUILD_DIR

# Start the OE container
sudo lxc-info -n openxt-oe | grep STOPPED >/dev/null && sudo lxc-start -d -n openxt-oe

# Wait 10 seconds and exit if the host doesn't respond
ping -w 10 192.168.123.101 >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Could not connect to openxt-oe, exiting."
    exit 1
fi

# Build
# TODO: fix first ssh
ssh -i ssh-key/openxt build@192.168.123.101 <<EOF
set -e
mkdir $BUILD_DIR
cd $BUILD_DIR
git clone openxt@192.168.123.1:git/openxt.git
cd openxt
cp example-config .config
cat >>.config <<EOF2
# TODO: those 2 values don't work, fix them
OPENXT_GIT_MIRROR="openxt@192.168.123.1:git"
OPENXT_GIT_PROTOCOL="ssh"
REPO_PROD_CACERT="/home/build/certs/prod-cacert.pem"
REPO_DEV_CACERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_CERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_KEY="/home/build/certs/dev-cakey.pem"
EOF2
./do_build.sh | tee build.log
EOF
