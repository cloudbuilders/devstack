#!/usr/bin/env bash

pushd $(cd $(dirname "$0")/.. && pwd)
source ./openrc

nova x509-create-cert
nova x509-get-root-cert

popd
