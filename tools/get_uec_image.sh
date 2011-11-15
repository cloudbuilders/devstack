#!/bin/bash
# get_uec_image.sh - Prepare Ubuntu UEC images

CACHEDIR=${CACHEDIR:-/opt/stack/cache}
ROOTSIZE=${ROOTSIZE:-2000}

# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=`cd $TOOLS_DIR/..; pwd`

# exit on error to stop unexpected errors
set -o errexit

usage() {
    echo "Usage: $0 - Prepare Ubuntu images"
    echo ""
    echo "$0 [-r rootsize] release imagefile"
    echo ""
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

    # Kill ourselves to signal any calling process
    trap 2; kill -2 $$
}

while getopts hr: c; do
    case $c in
        h)  usage
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

case $DIST_NAME in
    oneiric)    ;;
    natty)      ;;
    maverick)   ;;
    lucid)      ;;
    *)          echo "Unknown release: $DIST_NAME"
                usage
                ;;
esac

trap cleanup SIGHUP SIGINT SIGTERM SIGQUIT EXIT

# Check dependencies
if [ ! -x "`which qemu-img`" -o -z "`dpkg -l | grep cloud-utils`" ]; then
    # Missing KVM?
    apt_get install qemu-kvm cloud-utils
fi

# Find resize script
RESIZE=`which resize-part-image || which uec-resize-image`
if [ -z "$RESIZE" ]; then
    echo "resize tool from cloud-utils not found"
    exit 1
fi

# Get the UEC image
UEC_NAME=$DIST_NAME-server-cloudimg-amd64
if [ ! -d $CACHEDIR ]; then
    mkdir -p $CACHEDIR
fi
if [ ! -e $CACHEDIR/$UEC_NAME.tar.gz ]; then
    (cd $CACHEDIR && wget -N http://uec-images.ubuntu.com/$DIST_NAME/current/$UEC_NAME.tar.gz)
fi
if [ ! -d $CACHEDIR/$DIST_NAME ]; then
    mkdir -p $CACHEDIR/$DIST_NAME
    (cd $CACHEDIR/$DIST_NAME && tar Sxvzf ../$UEC_NAME.tar.gz)
fi

$RESIZE $CACHEDIR/$DIST_NAME/$UEC_NAME.img ${ROOTSIZE}M $IMG_FILE_TMP
mv $IMG_FILE_TMP $IMG_FILE

trap - SIGHUP SIGINT SIGTERM SIGQUIT EXIT

