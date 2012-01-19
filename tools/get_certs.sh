#!/usr/bin/env bash

# This can be switched to use the NOVA client once python-novaclient is updated

pushd $(cd $(dirname "$0")/.. && pwd)
source ./openrc

RESULT=`curl -s -d  "{\"auth\":{\"passwordCredentials\": {\"username\": \"$NOVA_USERNAME\", \"password\": \"$NOVA_PASSWORD\"}, \"tenantName\": \"$NOVA_PROJECT_ID\"}}" -H "Content-type: application/json" http://$HOST_IP:5000/v2.0/tokens`
TOKEN=`echo $RESULT | python -c "import sys; import json; res = json.loads(sys.stdin.read()); print res['access']['token']['id'];"`
ENDPOINT=`echo $RESULT | python -c "import sys; import json; res = json.loads(sys.stdin.read()); print [x for x in res['access']['serviceCatalog'] if x['type'] == 'compute'][0]['endpoints'][0]['publicURL'];"`

RESULT=`curl -s -X POST -H "x-auth-token: $TOKEN" $ENDPOINT/os-certificates`

echo $RESULT | python -c "import sys; import json; res = json.loads(sys.stdin.read()); print res['certificate']['data'];" > cert.pem
echo $RESULT | python -c "import sys; import json; res = json.loads(sys.stdin.read()); print res['certificate']['private_key'];" > pk.pem

curl -s -H "x-auth-token: $TOKEN" $ENDPOINT/os-certificates/root | python -c "import sys; import json; res = json.loads(sys.stdin.read()); print res['certificate']['data'];" > cacert.pem
popd
