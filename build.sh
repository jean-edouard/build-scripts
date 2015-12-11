#!/bin/bash -e

# Fetch git mirrors
for i in git/*.git; do
    echo -n "Fetching `basename $i`: "
    cd $i
    git fetch --all > /dev/null 2>&1
    git log -1 --pretty='tformat:%H'
    cd - > /dev/null
done | tee /tmp/git_heads_$BUILDID

# Create a build dir
BUILD_DIR=`date +%y%m%d`
mkdir $BUILD_DIR

# Start the OE container
sudo lxc-info -n openxt-oe | grep STOPPED >/dev/null && sudo lxc-start -d -n openxt-oe

# Wait a few seconds and exit if the host doesn't respond
ping -c 1 192.168.123.101 >/dev/null 2>&1 || ping -w 30 192.168.123.101 >/dev/null 2>&1 || {
    echo "Could not connect to openxt-oe, exiting."
    exit 1
}

# Build
ssh -i ssh-key/openxt -oStrictHostKeyChecking=no build@192.168.123.101 <<EOF
set -e
mkdir $BUILD_DIR
cd $BUILD_DIR
git clone openxt@192.168.123.1:git/openxt.git
cd openxt
cp example-config .config
cat >>.config <<EOF2
OPENXT_GIT_MIRROR="openxt@192.168.123.1/home/openxt/git"
OPENXT_GIT_PROTOCOL="ssh"
REPO_PROD_CACERT="/home/build/certs/prod-cacert.pem"
REPO_DEV_CACERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_CERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_KEY="/home/build/certs/dev-cakey.pem"
EOF2
./do_build.sh | tee build.log
EOF
