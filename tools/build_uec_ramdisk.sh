#!/usr/bin/env bash
# build_uec_ramdisk.sh - Build RAM disk images based on UEC image

# exit on error to stop unexpected errors
set -o errexit

if [ ! "$#" -eq "1" ]; then
    echo "$0 builds a gziped Ubuntu OpenStack install"
    echo "usage: $0 dest"
    exit 1
fi

# Make sure that we have the proper version of ubuntu (only works on oneiric)
if ! egrep -q "oneiric" /etc/lsb-release; then
    echo "This script only works with ubuntu oneiric."
    exit 1
fi

# Output dest image
DEST_FILE=$1

# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=`cd $TOOLS_DIR/..; pwd`

cd $TOP_DIR

# Source params
source ./stackrc

# Ubuntu distro to install
DIST_NAME=${DIST_NAME:-oneiric}

# Configure how large the VM should be
GUEST_SIZE=${GUEST_SIZE:-2G}

# exit on error to stop unexpected errors
set -o errexit
set -o xtrace

# Abort if localrc is not set
if [ ! -e $TOP_DIR/localrc ]; then
    echo "You must have a localrc with ALL necessary passwords defined before proceeding."
    echo "See stack.sh for required passwords."
    exit 1
fi

# Install deps if needed
DEPS="kvm libvirt-bin kpartx cloud-utils curl"
apt-get install -y --force-yes $DEPS

# Where to store files and instances
CACHEDIR=${CACHEDIR:-/opt/stack/cache}
WORK_DIR=${WORK_DIR:-/opt/kvmstack}

# Where to store images
image_dir=$WORK_DIR/images/$DIST_NAME
mkdir -p $image_dir

# Get the base image if it does not yet exist
if [ ! -e $image_dir/disk ]; then
    $TOOLS_DIR/get_uec_image.sh -f raw -r 2000M $DIST_NAME $image_dir/disk
fi

# Configure the root password of the vm to be the same as ``ADMIN_PASSWORD``
ROOT_PASSWORD=${ADMIN_PASSWORD:-password}

# Name of our instance, used by libvirt
GUEST_NAME=${GUEST_NAME:-devstack}

# Pre-load the image with basic environment
cp $image_dir/disk $image_dir/disk-primed
$TOOLS_DIR/warm_apts_and_pips.sh $image_dir/disk-primed
$TOOLS_DIR/setup_stack_user.sh $image_dir/disk-primed

# Back to devstack
cd $TOP_DIR

GUEST_NETWORK=${GUEST_NETWORK:-1}
GUEST_RECREATE_NET=${GUEST_RECREATE_NET:-yes}
GUEST_IP=${GUEST_IP:-192.168.$GUEST_NETWORK.50}
GUEST_CIDR=${GUEST_CIDR:-$GUEST_IP/24}
GUEST_NETMASK=${GUEST_NETMASK:-255.255.255.0}
GUEST_GATEWAY=${GUEST_GATEWAY:-192.168.$GUEST_NETWORK.1}
GUEST_MAC=${GUEST_MAC:-"02:16:3e:07:69:`printf '%02X' $GUEST_NETWORK`"}
GUEST_RAM=${GUEST_RAM:-1524288}
GUEST_CORES=${GUEST_CORES:-1}

exit 1

DEST_FILE_TMP=`mktemp $DEST_FILE.XXXXXX`
if [ ! -r $DEST_FILE ]; then

# dd to fs image

    mv $DEST_FILE_TMP $DEST_FILE
fi
rm -f $DEST_FILE_TMP

MNT_DIR=`mktemp -d --tmpdir mntXXXXXXXX`
mount -t ext4 -o loop $DEST_FILE $MNT_DIR
cp -p /etc/resolv.conf $MN_TDIR/etc/resolv.conf

# We need to install a non-virtual kernel and modules to boot from
if [ ! -r "`ls $MNT_DIR/boot/vmlinuz-*-generic | head -1`" ]; then
    chroot $MNT_DIR apt-get install -y linux-generic
fi

# git clone only if directory doesn't exist already.  Since ``DEST`` might not
# be owned by the installation user, we create the directory and change the
# ownership to the proper user.
function git_clone {

    # clone new copy or fetch latest changes
    CHECKOUT=${MNT_DIR}$2
    if [ ! -d $CHECKOUT ]; then
        mkdir -p $CHECKOUT
        git clone $1 $CHECKOUT
    else
        pushd $CHECKOUT
        git fetch
        popd
    fi

    # FIXME(ja): checkout specified version (should works for branches and tags)

    pushd $CHECKOUT
    # checkout the proper branch/tag
    git checkout $3
    # force our local version to be the same as the remote version
    git reset --hard origin/$3
    popd

    # give ownership to the stack user
    chroot $MNT_DIR chown -R stack $2
}

git_clone $NOVA_REPO $DEST/nova $NOVA_BRANCH
git_clone $GLANCE_REPO $DEST/glance $GLANCE_BRANCH
git_clone $KEYSTONE_REPO $DEST/keystone $KEYSTONE_BRANCH
git_clone $NOVNC_REPO $DEST/novnc $NOVNC_BRANCH
git_clone $HORIZON_REPO $DEST/horizon $HORIZON_BRANCH
git_clone $NOVACLIENT_REPO $DEST/python-novaclient $NOVACLIENT_BRANCH
git_clone $OPENSTACKX_REPO $DEST/openstackx $OPENSTACKX_BRANCH
git_clone $CITESTS_REPO $DEST/openstack-integration-tests $CITESTS_BRANCH

# Use this version of devstack
rm -rf $MNT_DIR/$DEST/devstack
cp -pr $CWD $MNT_DIR/$DEST/devstack
chroot $MNT_DIR chown -R stack $DEST/devstack

# Configure host network for DHCP
mkdir -p $MNT_DIR/etc/network
cat > $MNT_DIR/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Set hostname
echo "ramstack" >$MNTDIR/etc/hostname
echo "127.0.0.1		localhost	ramstack" >$MNTDIR/etc/hosts

# Configure the runner
RUN_SH=$MNT_DIR/$DEST/run.sh
cat > $RUN_SH <<EOF
#!/usr/bin/env bash

# Get IP range
set \`ip addr show dev eth0 | grep inet\`
PREFIX=\`echo \$2 | cut -d. -f1,2,3\`
export FLOATING_RANGE="\$PREFIX.224/27"

# Kill any existing screens
killall screen

# Run stack.sh
cd $DEST/devstack && \$STACKSH_PARAMS ./stack.sh > $DEST/run.sh.log
echo >> $DEST/run.sh.log
echo >> $DEST/run.sh.log
echo "All done! Time to start clicking." >> $DEST/run.sh.log
EOF

# Make the run.sh executable
chmod 755 $RUN_SH
chroot $MNTDIR chown stack $DEST/run.sh

umount $MNTDIR
rmdir $MNTDIR

# set user-data
cat > $vm_dir/uec/user-data<<EOF
#!/bin/bash
# hostname needs to resolve for rabbit
sed -i "s/127.0.0.1/127.0.0.1 \`hostname\`/" /etc/hosts
apt-get update
apt-get install git sudo -y
git clone https://github.com/cloudbuilders/devstack.git
cd devstack
git remote set-url origin `cd $TOP_DIR; git remote show origin | grep Fetch | awk '{print $3}'`
git fetch
git checkout `git rev-parse HEAD`
cat > localrc <<LOCAL_EOF
ROOTSLEEP=0
`cat $TOP_DIR/localrc`
LOCAL_EOF
# Disable byobu
/usr/bin/byobu-disable
EOF

# Setup stack user with our key
CONFIGURE_STACK_USER=${CONFIGURE_STACK_USER:-yes}
if [[ -e ~/.ssh/id_rsa.pub  && "$CONFIGURE_STACK_USER" = "yes" ]]; then
    PUB_KEY=`cat  ~/.ssh/id_rsa.pub`
    cat >> $vm_dir/uec/user-data<<EOF
EOF
fi


# Run stack.sh
cat >> $vm_dir/uec/user-data<<EOF
./stack.sh
EOF

# (re)start a metadata service
(
  pid=`lsof -iTCP@192.168.$GUEST_NETWORK.1:4567 -n | awk '{print $2}' | tail -1`
  [ -z "$pid" ] || kill -9 $pid
)
cd $vm_dir/uec
python meta.py 192.168.$GUEST_NETWORK.1:4567 &

# Create the instance
virsh create $vm_dir/libvirt.xml

# Tail the console log till we are done
WAIT_TILL_LAUNCH=${WAIT_TILL_LAUNCH:-1}
if [ "$WAIT_TILL_LAUNCH" = "1" ]; then
    set +o xtrace
    # Done creating the container, let's tail the log
    echo
    echo "============================================================="
    echo "                          -- YAY! --"
    echo "============================================================="
    echo
    echo "We're done launching the vm, about to start tailing the"
    echo "stack.sh log. It will take a second or two to start."
    echo
    echo "Just CTRL-C at any time to stop tailing."

    while [ ! -e "$vm_dir/console.log" ]; do
      sleep 1
    done

    tail -F $vm_dir/console.log &

    TAIL_PID=$!

    function kill_tail() {
        kill $TAIL_PID
        exit 1
    }

    # Let Ctrl-c kill tail and exit
    trap kill_tail SIGINT

    echo "Waiting stack.sh to finish..."
    while ! egrep -q '^stack.sh (completed|failed)' $vm_dir/console.log ; do
        sleep 1
    done

    set -o xtrace

    kill $TAIL_PID

    if ! grep -q "^stack.sh completed in" $vm_dir/console.log; then
        exit 1
    fi
    echo ""
    echo "Finished - Zip-a-dee Doo-dah!"
fi
