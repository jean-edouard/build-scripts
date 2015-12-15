#!/bin/bash -e

DUDE=`whoami`
DUDE_ID=`id -u ${DUDE}`
IP_C=$(( 150 + ${DUDE_ID} % 100 ))

# Fetch git mirrors
for i in /home/git/${DUDE}/*.git; do
    echo -n "Fetching `basename $i`: "
    cd $i
    git fetch --all > /dev/null 2>&1
    git log -1 --pretty='tformat:%H'
    cd - > /dev/null
done | tee /tmp/git_heads_$BUILDID

# Start the git service if needed
kill -0 `cat /tmp/openxt_git.pid 2>/dev/null` 2>/dev/null || {
    rm -f /tmp/openxt_git.pid
    git daemon --base-path=/home/git --pid-file=/tmp/openxt_git.pid --detach --syslog --export-all
    chmod 666 /tmp/openxt_git.pid
}

# Create a build dir
BUILD_DIR=`date +%y%m%d`
mkdir $BUILD_DIR

# Start the OE container
sudo lxc-info -n ${DUDE}-oe | grep STOPPED >/dev/null && sudo lxc-start -d -n ${DUDE}-oe

# Wait a few seconds and exit if the host doesn't respond
ping -c 1 192.168.${IP_C}.101 >/dev/null 2>&1 || ping -w 30 192.168.${IP_C}.101 >/dev/null 2>&1 || {
    echo "Could not connect to openxt-oe, exiting."
    exit 1
}

# Build
ssh -i ssh-key/openxt -oStrictHostKeyChecking=no build@192.168.${IP_C}.101 <<EOF
set -e
mkdir $BUILD_DIR
cd $BUILD_DIR
git clone git://192.168.${IP_C}.1/${DUDE}/openxt.git
cd openxt
cp example-config .config
cat >>.config <<EOF2
OPENXT_GIT_MIRROR="192.168.${IP_C}.1/${DUDE}"
OPENXT_GIT_PROTOCOL="git"
REPO_PROD_CACERT="/home/build/certs/prod-cacert.pem"
REPO_DEV_CACERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_CERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_KEY="/home/build/certs/dev-cakey.pem"
EOF2
./do_build.sh | tee build.log
EOF
