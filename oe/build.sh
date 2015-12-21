#!/bin/sh

set -e
mkdir $BUILD_DIR
cd $BUILD_DIR
git clone git://192.168.${IP_C}.1/${DUDE}/openxt.git
cd openxt
cp example-config .config
cat >>.config <<EOF
OPENXT_GIT_MIRROR="192.168.${IP_C}.1/${DUDE}"
OPENXT_GIT_PROTOCOL="git"
REPO_PROD_CACERT="/home/build/certs/prod-cacert.pem"
REPO_DEV_CACERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_CERT="/home/build/certs/dev-cacert.pem"
REPO_DEV_SIGNING_KEY="/home/build/certs/dev-cakey.pem"
EOF
./do_build.sh | tee build.log
