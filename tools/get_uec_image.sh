#!/bin/bash
# get_uec_image.sh - Prepare Ubuntu images in various formats
#
# Supported formats: qcow (kvm), vmdk (vmserver), vdi (vbox), vhd (vpc), raw
#
# Required to run as root

CACHEDIR=${CACHEDIR:-/var/cache/devstack}
FORMAT=${FORMAT:-qcow2}
ROOTSIZE=${ROOTSIZE:-2000}
MIN_PKGS=${MIN_PKGS:-"apt-utils gpgv openssh-server"}

# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=`cd $TOOLS_DIR/..; pwd`

usage() {
    echo "Usage: $0 - Prepare Ubuntu images"
    echo ""
    echo "$0 [-f format] [-r rootsize] release imagefile"
    echo ""
    echo "-f format - image format: qcow2 (default), vmdk, vdi, vhd, xen, raw, fs"
    echo "-r size   - root fs size in MB (min 2000MB)"
    echo "release   - Ubuntu release: jaunty - oneric"
    echo "imagefile - output image file"
    exit 1
}

# Clean up any resources that may be in use
cleanup() {
    set +o errexit

    # Mop up temporary files
    if [ -n "$IMG_FILE_TMP" -a -e "$IMG_FILE_TMP" ]; then
        rm -f $IMG_FILE_TMP
    fi

    # Release NBD devices
    if [ -n "$NBD" ]; then
        qemu-nbd -d $NBD
    fi

    # Kill ourselves to signal any calling process
    trap 2; kill -2 $$
}

while getopts f:hmr: c; do
    case $c in
        f)  FORMAT=$OPTARG
            ;;
        h)  usage
            ;;
        m)  MINIMAL=1
            ;;
        r)  ROOTSIZE=$OPTARG
            if [[ $ROOTSIZE < 2000 ]]; then
                echo "root size must be greater than 2000MB"
                exit 1
            fi
            ;;
    esac
done
shift `expr $OPTIND - 1`

if [ ! "$#" -eq "2" ]; then
    usage
fi

# Default args
DIST_NAME=$1
IMG_FILE=$2
IMG_FILE_TMP=`mktemp $IMG_FILE.XXXXXX`

case $FORMAT in
    kvm|qcow2)  FORMAT=qcow2
                QFORMAT=qcow2
                ;;
    vmserver|vmdk)
                FORMAT=vmdk
                QFORMAT=vmdk
                ;;
    vbox|vdi)   FORMAT=vdi
                QFORMAT=vdi
                ;;
    vhd|vpc)    FORMAT=vhd
                QFORMAT=vpc
                ;;
    xen)        FORMAT=raw
                QFORMAT=raw
                ;;
    raw)        FORMAT=raw
                QFORMAT=raw
                ;;
    *)          echo "Unknown format: $FORMAT"
                usage
esac

case $DIST_NAME in
    oneiric)    ;;
    natty)      ;;
    maverick)   ;;
    lucid)      ;;
    karmic)     ;;
    jaunty)     ;;
    *)          echo "Unknown release: $DIST_NAME"
                usage
                ;;
esac

trap cleanup SIGHUP SIGINT SIGTERM

# Prepare the base image

# Get the UEC image
UEC_NAME=$DIST_NAME-server-cloudimg-amd64
if [ ! -e $CACHEDIR/$UEC_NAME-disk1.img ]; then
    (cd $CACHEDIR && wget -N http://uec-images.ubuntu.com/$DIST_NAME/current/$UEC_NAME-disk1.img)
fi

if [ "$FORMAT" = "qcow2" ]; then
    # Just copy image
    cp -p $CACHEDIR/$UEC_NAME-disk1.img $IMG_FILE_TMP
else
    # Convert image
    qemu-img convert -O $QFORMAT $CACHEDIR/$UEC_NAME-disk1.img $IMG_FILE_TMP
fi

# Resize the image if necessary
if [ $ROOTSIZE -gt 2000 ]; then
    # Resize the container
    qemu-img resize $IMG_FILE_TMP +$((ROOTSIZE - 2000))M
fi

# Finds the next available NBD device
# Exits script if error connecting or none free
# map_nbd image
# returns full nbd device path
function map_nbd {
    for i in `seq 0 15`; do
        if [ ! -e /sys/block/nbd$i/pid ]; then
            NBD=/dev/nbd$i
            # Connect to nbd and wait till it is ready
            qemu-nbd -c $NBD $1
            if ! timeout 60 sh -c "while ! [ -e ${NBD}p1 ]; do sleep 1; done"; then
                echo "Couldn't connect $NBD"
                exit 1
            fi
            break
        fi
    done
    if [ -z "$NBD" ]; then
        echo "No free NBD slots"
        exit 1
    fi
    echo $NBD
}

# Set up nbd
modprobe nbd max_part=63
NBD=`map_nbd $IMG_FILE_TMP`

# Resize partition 1 to full size of the disk image
echo "d
n
p
1
2

t
83
a
1
w
" | fdisk $NBD
e2fsck -f -p ${NBD}p1
resize2fs ${NBD}p1

# Do some preliminary installs
MNTDIR=`mktemp -d mntXXXXXXXX`
mount -t ext4 ${NBD}p1 $MNTDIR

# Install our required packages
cp -p files/sources.list $MNTDIR/etc/apt/sources.list
sed -e "s,%DIST%,$DIST_NAME,g" -i $MNTDIR/etc/apt/sources.list
cp -p /etc/resolv.conf $MNTDIR/etc/resolv.conf
chroot $MNTDIR apt-get update
chroot $MNTDIR apt-get install -y $MIN_PKGS
rm -f $MNTDIR/etc/resolv.conf

umount $MNTDIR
rmdir $MNTDIR
qemu-nbd -d $NBD
NBD=""

mv $IMG_FILE_TMP $IMG_FILE
