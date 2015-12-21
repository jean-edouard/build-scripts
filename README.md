# build-scripts
Scripts to setup and run OpenXT builds in containers

## How to use

- Do a fresh Debian install. Recommended configuration: bare-metal 64 bits Jessie
- Login as root
- Install git
- Clone this repository and `cd` to it
- Optional: edit setup.sh to change the Debian mirror
- Run `./setup.sh -u user` to setup a build environment for "user"
- Logout and login as user
- Run ./build.sh
