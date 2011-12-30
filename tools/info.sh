#!/usr/bin/env bash
#
# info.sh - Produce a report on the state of devstack installs
#

function usage {
    echo "$0 - Report on the devstack configuration"
    echo ""
    echo "Usage: $0"
    exit 1
}

if [ "$1" = "-h" ]; then
    usage
fi

# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=`cd $TOOLS_DIR/..; pwd`

# Source params
source ./stackrc

DEST=${DEST:-/opt/stack}
FILES=$TOP_DIR/files
if [[ ! -d $FILES ]]; then
    echo "ERROR: missing devstack/files - did you grab more than just stack.sh?"
    exit 1
fi

# git_report <dir>
function git_report() {
    local dir=$1
    local ref=""
    local head=""
    if [[ -d $dir/.git ]]; then
        cd $dir
        ref=`cat .git/HEAD | cut -d' ' -f2`
        head=`cat .git/$ref`
        proj=`basename $dir`
        echo "git|$proj|$head"
    fi
}

#set -o xtrace

# Repos
# -----

for i in $DEST/*; do
    if [[ -d $i ]]; then
        git_report $i
    fi
done

# localrc
# -------

if [[ -r $TOP_DIR/localrc ]]; then
    echo ""
    echo "localrc:"
    sed -e '
        /PASSWORD/d;
        /^#/d;
    ' $TOP_DIR/localrc | sort
fi

# OS
# --

GetOSInfo() {
    # Figure out which vedor we are
    if [ -r /etc/lsb-release ]; then
        . /etc/lsb-release
        VENDORNAME=$DISTRIB_ID
        RELEASE=$DISTRIB_RELEASE
    else
        for r in RedHat CentOS Fedora; do
            VENDORPKG="`echo $r | tr [:upper:] [:lower:]`-release"
            VENDORNAME=$r
            RELEASE=`rpm -q --queryformat '%{VERSION}' $VENDORPKG`
            if [ $? = 0 ]; then
                break
            fi
            VENDORNAME=""
        done
        # Get update level
        if [ -n "`grep Update /etc/redhat-release`" ]; then
            # Get update
            UPDATE=`cat /etc/redhat-release | sed s/.*Update\ // | sed s/\)$//`
        else
            # Assume update 0
            UPDATE=0
        fi
    fi

    echo "os|vendor=$VENDORNAME"
    echo "os|release=$RELEASE"
    if [ -n "$UPDATE" ]; then
        echo "os|version=$UPDATE"
    fi
}

# - We are going to install packages only for the services needed.
# - We are parsing the packages files and detecting metadatas.
#  - If there is a NOPRIME as comment mean we are not doing the install
#    just yet.
#  - If we have the meta-keyword dist:DISTRO or
#    dist:DISTRO1,DISTRO2 it will be installed only for those
#    distros (case insensitive).
function get_packages() {
    local file_to_parse="general"
    local service
#set -o xtrace

    for service in ${ENABLED_SERVICES//,/ }; do
        # Allow individual services to specify dependencies
        if [[ -e $FILES/apts/${service} ]]; then
            file_to_parse="${file_to_parse} $service"
        fi
        if [[ $service == n-* ]]; then
            if [[ ! $file_to_parse =~ nova ]]; then
                file_to_parse="${file_to_parse} nova"
            fi
        elif [[ $service == g-* ]]; then
            if [[ ! $file_to_parse =~ glance ]]; then
                file_to_parse="${file_to_parse} glance"
            fi
        elif [[ $service == key* ]]; then
            if [[ ! $file_to_parse =~ keystone ]]; then
                file_to_parse="${file_to_parse} keystone"
            fi
        fi
    done

    for file in ${file_to_parse}; do
        local fname=${FILES}/apts/${file}
        local OIFS line package distros distro
        [[ -e $fname ]] || { echo "missing: $fname"; exit 1 ;}

        OIFS=$IFS
        IFS=$'\n'
        for line in $(<${fname}); do
            if [[ $line =~ "NOPRIME" ]]; then
                continue
            fi

            if [[ $line =~ (.*)#.*dist:([^ ]*) ]]; then # We are using BASH regexp matching feature.
                        package=${BASH_REMATCH[1]}
                        distros=${BASH_REMATCH[2]}
                        for distro in ${distros//,/ }; do  #In bash ${VAR,,} will lowecase VAR
                            [[ ${distro,,} == ${DISTRO,,} ]] && echo $package
                        done
                        continue
            fi

            echo ${line%#*}
        done
        IFS=$OIFS
    done
}

echo ""
GetOSInfo

for p in $(get_packages); do
    ver=`dpkg -s $p 2>/dev/null | grep '^Version: ' | cut -d' ' -f2`
    echo "pkg|${p}|${ver}"
done

for p in $(cat $FILES/pips/* | uniq | tr '-' '_' | tr [:upper:] [:lower:] ); do
    [[ "$p" = "_e" ]] && continue
    [[ ver=`echo $p | cut -d'=' -f3` ]] && p=`echo $p | cut -d'=' -f1`
    ver=""
    # Attempt to get version
    pipdir=/usr/local/lib/python2.7/dist-packages
    d=`ls -d $pipdir/$p-*-info 2>/dev/null | head -1`
    if [[ -d "$d" && -f $d/PKG-INFO ]]; then
        ver=`cat $d/PKG-INFO | grep '^Version: ' | cut -d' ' -f2`
    fi
    echo "pip|${p}|${ver}"
done