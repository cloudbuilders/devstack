#!/usr/bin/env bash

# we will use the ``euca2ools`` cli tool that wraps the python boto
# library to test ec2 compatibility
#

# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace

# Settings
# ========

# Use openrc + stackrc + localrc for settings
pushd $(cd $(dirname "$0")/.. && pwd)
source ./openrc

# Get Certificates
x509-get-root-certs
nova x509-create-cert
popd

# Max time to wait for image to be registered
REGISTER_TIMEOUT=${REGISTER_TIMEOUT:-15}

BUCKET=testbucket
IMAGE=bundle.img
truncate -s 5M /tmp/$IMAGE
euca-bundle-image -i /tmp/$IMAGE


euca-upload-bundle -b $BUCKET -m /tmp/$IMAGE.manifest.xml
$AMI=`euca-resister $BUCKET/$IMAGE.manifest.xml | cut -f2`


# Wait just a tick for everything above to complete so terminate doesn't fail
if ! timeout $REGISTER_TIMEOUT sh -c "while euca-describe-images | grep $AMI | grep available; do sleep 1; done"; then
    echo "Image $AMI not available within $REGISTER_TIMEOUT seconds"
    exit 1
fi
