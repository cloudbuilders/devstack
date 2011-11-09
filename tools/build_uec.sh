#!/usr/bin/env bash

# Make sure that we have the proper version of ubuntu (only works on oneiric)
if ! egrep -q "oneiric" /etc/lsb-release; then
    echo "This script only works with ubuntu oneiric."
    exit 1
fi

# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=`cd $TOOLS_DIR/..; pwd`

cd $TOP_DIR

# Source params
source ./stackrc

# Ubuntu distro to install
DIST_NAME=${DIST_NAME:-oneiric}

# Configure how large the VM should be
GUEST_SIZE=${GUEST_SIZE:-10G}

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
DEPS="kvm libvirt-bin kpartx cloud-utils"
dpkg -l $DEPS || apt-get install -y --force-yes $DEPS

# Where to store files and instances
WORK_DIR=${WORK_DIR:-/opt/kvmstack}

# Where to store images
image_dir=$WORK_DIR/images/$DIST_NAME
mkdir -p $image_dir

# Original version of built image
uec_url=http://uec-images.ubuntu.com/$DIST_NAME/current/$DIST_NAME-server-cloudimg-amd64.tar.gz
tarball=$image_dir/$(basename $uec_url)

# download the base uec image if we haven't already
if [ ! -f $tarball ]; then
    curl $uec_url -o $tarball
    (cd $image_dir && tar -Sxvzf $tarball)
    resize-part-image $image_dir/*.img $GUEST_SIZE $image_dir/disk
    cp $image_dir/*-vmlinuz-virtual $image_dir/kernel
fi


# Configure the root password of the vm to be the same as ``ADMIN_PASSWORD``
ROOT_PASSWORD=${ADMIN_PASSWORD:-password}

# Name of our instance, used by libvirt
GUEST_NAME=${GUEST_NAME:-devstack}

# Mop up after previous runs
virsh destroy $GUEST_NAME || true

# Where this vm is stored
vm_dir=$WORK_DIR/instances/$GUEST_NAME

# Create vm dir and remove old disk
mkdir -p $vm_dir
rm -f $vm_dir/disk

# Create a copy of the base image
qemu-img create -f qcow2 -b $image_dir/disk $vm_dir/disk

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

# libvirt.xml configuration
NET_XML=$vm_dir/net.xml
cat > $NET_XML <<EOF
<network>
  <name>devstack-$GUEST_NETWORK</name>
  <bridge name="stackbr%d" />
  <forward/>
  <ip address="$GUEST_GATEWAY" netmask="$GUEST_NETMASK">
    <dhcp>
      <range start='192.168.$GUEST_NETWORK.2' end='192.168.$GUEST_NETWORK.127' />
    </dhcp>
  </ip>
</network>
EOF

if [[ "$GUEST_RECREATE_NET" == "yes" ]]; then
    virsh net-destroy devstack-$GUEST_NETWORK || true
    # destroying the network isn't enough to delete the leases
    rm -f /var/lib/libvirt/dnsmasq/devstack-$GUEST_NETWORK.leases
    virsh net-create $vm_dir/net.xml
fi

# libvirt.xml configuration
LIBVIRT_XML=$vm_dir/libvirt.xml
cat > $LIBVIRT_XML <<EOF
<domain type='kvm'>
  <name>$GUEST_NAME</name>
  <memory>$GUEST_RAM</memory>
  <os>
    <type>hvm</type>
    <kernel>$image_dir/kernel</kernel>
    <cmdline>root=/dev/vda ro console=ttyS0 init=/usr/lib/cloud-init/uncloud-init ds=nocloud-net;s=http://192.168.$GUEST_NETWORK.1:4567/ ubuntu-pass=ubuntu</cmdline>
  </os>
  <features>
    <acpi/>
  </features>
  <clock offset='utc'/>
  <vcpu>$GUEST_CORES</vcpu>
  <devices>
    <disk type='file'>
      <driver type='qcow2'/>
      <source file='$vm_dir/disk'/>
      <target dev='vda' bus='virtio'/>
    </disk>

    <interface type='network'>
      <source network='devstack-$GUEST_NETWORK'/>
    </interface>
        
    <!-- The order is significant here.  File must be defined first -->
    <serial type="file">
      <source path='$vm_dir/console.log'/>
      <target port='1'/>
    </serial>

    <console type='pty' tty='/dev/pts/2'>
      <source path='/dev/pts/2'/>
      <target port='0'/>
    </console>

    <serial type='pty'>
      <source path='/dev/pts/2'/>
      <target port='0'/>
    </serial>

    <graphics type='vnc' port='-1' autoport='yes' keymap='en-us' listen='0.0.0.0'/>
  </devices>
</domain>
EOF


rm -rf $vm_dir/uec
cp -r $TOOLS_DIR/uec $vm_dir/uec

# set metadata
cat > $vm_dir/uec/meta-data<<EOF
hostname: $GUEST_NAME
instance-id: i-hop
instance-type: m1.ignore
local-hostname: $GUEST_NAME.local
EOF

# set metadata
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
