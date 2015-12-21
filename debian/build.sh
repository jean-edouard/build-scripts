#!/bin/sh

set -e

DUDE=%DUDE%
BUILD_DIR=%BUILD_DIR%
IP_C=%IP_C%

# Build
rm -rf pv-linux-drivers
git clone -b sbuild https://github.com/jean-edouard/pv-linux-drivers.git
mkdir -p wheezy
cd wheezy
sbuild --dist=wheezy --arch-all ../pv-linux-drivers/xenmou
cd - >/dev/null
mkdir -p jessie
cd jessie
sbuild --dist=jessie --arch-all ../pv-linux-drivers/xenmou
cd - >/dev/null
