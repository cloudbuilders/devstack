#!/bin/bash
BIN_DIR=${BIN_DIR:-./bin}
# Tenants
$BIN_DIR/ksl $* tenant add name=admin id=admin
$BIN_DIR/ksl $* tenant add name=demo id=demo
$BIN_DIR/ksl $* tenant add name=invisible_to_admin id=invisible_to_admin

# Users
$BIN_DIR/ksl $* user add name=admin id=admin password=%ADMIN_PASSWORD% \
    tenants[]=admin \
    tenants[]=demo
$BIN_DIR/ksl $* user add name=demo id=demo password=%ADMIN_PASSWORD% \
    tenants[]=demo \
    tenants[]=invisible_to_admin

# Roles
$BIN_DIR/ksl $* extras add user_id=admin tenant_id=admin \
    roles[]=Admin
$BIN_DIR/ksl $* extras add user_id=demo tenant_id=demo \
    roles[]=sysadmin \
    roles[]=netadmin


#$BIN_DIR/ksl $* role add Member
#$BIN_DIR/ksl $* role add KeystoneAdmin
#$BIN_DIR/ksl $* role add KeystoneServiceAdmin
#$BIN_DIR/ksl $* role add sysadmin
#$BIN_DIR/ksl $* role add netadmin

#$BIN_DIR/ksl $* role grant Admin admin admin
#$BIN_DIR/ksl $* role grant Member demo demo
#$BIN_DIR/ksl $* role grant sysadmin demo demo
#$BIN_DIR/ksl $* role grant netadmin demo demo
#$BIN_DIR/ksl $* role grant Member demo invisible_to_admin
#$BIN_DIR/ksl $* role grant Admin admin demo
#$BIN_DIR/ksl $* role grant Admin admin
#$BIN_DIR/ksl $* role grant KeystoneAdmin admin
#$BIN_DIR/ksl $* role grant KeystoneServiceAdmin admin

## Services
#$BIN_DIR/ksl $* service add nova compute "Nova Compute Service"
#$BIN_DIR/ksl $* service add glance image "Glance Image Service"
#$BIN_DIR/ksl $* service add keystone identity "Keystone Identity Service"
#$BIN_DIR/ksl $* service add swift object-store "Swift Service"

#endpointTemplates
#$BIN_DIR/ksl $* endpointTemplates add RegionOne nova http://%HOST_IP%:8774/v1.1/%tenant_id% http://%HOST_IP%:8774/v1.1/%tenant_id%  http://%HOST_IP%:8774/v1.1/%tenant_id% 1 1
#$BIN_DIR/ksl $* endpointTemplates add RegionOne glance http://%HOST_IP%:9292/v1.1/%tenant_id% http://%HOST_IP%:9292/v1.1/%tenant_id% http://%HOST_IP%:9292/v1.1/%tenant_id% 1 1
#$BIN_DIR/ksl $* endpointTemplates add RegionOne keystone http://%HOST_IP%:5000/v2.0 http://%HOST_IP%:35357/v2.0 http://%HOST_IP%:5000/v2.0 1 1
#$BIN_DIR/ksl $* endpointTemplates add RegionOne swift http://%HOST_IP%:8080/v1/AUTH_%tenant_id% http://%HOST_IP%:8080/ http://%HOST_IP%:8080/v1/AUTH_%tenant_id% 1 1

# Tokens
#$BIN_DIR/ksl $* token add %SERVICE_TOKEN% admin admin 2015-02-05T00:00

## EC2 related creds - note we are setting the secret key to ADMIN_PASSWORD
## but keystone doesn't parse them - it is just a blob from keystone's
## point of view
#$BIN_DIR/ksl $* credentials add admin EC2 'admin' '%ADMIN_PASSWORD%' admin || echo "no support for adding credentials"
#$BIN_DIR/ksl $* credentials add demo EC2 'demo' '%ADMIN_PASSWORD%' demo || echo "no support for adding credentials"
