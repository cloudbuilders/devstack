#!/usr/bin/env bash

# Utility script to clean up after running exercise.sh, so that
# the exercise script can be used as a functionality or acceptance
# test on real operational hardware.

# Settings
# ========

# Like stack.sh and exercise.sh, this script honors the same options
# as specified in stackrc/openrc/localrc so that it can clean up after
# an exercise.sh run.  See stack.sh for more details

source ./openrc

# Options
# -------

# Exit on errors so that underlying problems can be quickly
# diagnosed

set -o errexit

# Print all commands as they run to help in troubleshooting.

set -o xtrace

# Ensure that we exit on unbound values so we don't accidentally
# do something horribly wrong.

set -o nounset

# Secgroup Cleanup
# ----------------

# the floating_ips.sh exercise creates security groups to test
# pingability.  It fails if these security groups already exist.
# To allow exercise.sh to be used to iteratively test a real
# installation, these security groups should be cleaned up each
# run.

# This will need to be changed if the security group name
# in floating_ips changes.

SECGROUP=test_secgroup

if ( nova secgroup-list | grep ${SECGROUP}); then
    nova secgroup-delete ${SECGROUP}
fi

# Instance Cleanup
# ----------------

# Instances are also created for each floating_ips run.
# While the existence of an instance of a particular name
# will not cause exercise.sh to fail, it will pollute compute
# controllers, and should be removed if using exercise.sh as
# an acceptance test.

# We'll delete one instance at a time, in case there are
# multiple instances with the same test name

# The hardcoded name will have to be changed if the instance name
# in exercises/floating_ips.sh changes

NAME=myserver

while ( /bin/true ); do
    ID=$(nova show "${NAME}" | grep " id " | cut -d'|' -f 3)
    if [ "$ID" == "" ]; then
        break;
    fi

    nova delete ${ID}

    # Certainly destroy time is related to time to become active,
    # so we'll use the same variable to timeout the destroy
    if ! timeout $ACTIVE_TIMEOUT sh -c "while nova show ${ID}; do sleep 1; done"; then
        echo "Server ${ID} wouldn't shut down!"
        exit 1
    fi
done


