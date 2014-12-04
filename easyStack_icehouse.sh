#!/bin/sh
HOSTNAME="UPYUN-M1"
IPADDR="192.168.13.250"
VERSION="icehouse"
SCRIPT="easyStack_$VERSION.sh"
KEYPAIR="upyun"
PASSWD="password"
TIME_SRV="133.100.11.8"
ZONE="Asia/Shanghai"
COMMAND=`pwd`"/$SCRIPT"

VIRT_TYPE="kvm"

###  user|pass|role|tenant
ADMIN_SETTING="admin|admin_secret|admin|admin"
SYSTEM_COMPONENT="nova|nova_secret|admin|service glance|glance_secret|admin|service swift|swift_secret|admin|service cinder|cinder_secret|admin|service"
REGION="RegionOne"
KEYS_ADMIN_URL="$IPADDR:35357/v2.0"
KEYS_URL="$IPADDR:5000/v2.0"
IMAGE_URL="$IPADDR:9292/v1"
NOVA_URL="$IPADDR:8774/v2/\$(tenant_id)s"
VOLUME_URL="$IPADDR:8776/v1/\$(tenant_id)s"
OBG_STORE_URL="$IPADDR:8080/v1/AUTH_\$(tenant_id)s"
EC2_URL="$IPADDR:8773/services/Cloud"

### Color setting
RED_COL="\\033[1;31m"  # red color
GREEN_COL="\\033[32;1m"     # green color
BLUE_COL="\\033[34;1m"    # blue color
YELLOW_COL="\\033[33;1m"         # yellow color
NORMAL_COL="\\033[0;39m"

###
KS_DIR="/var/lib/keystone"
KS_RCONFIG="$KS_DIR/ks_rc_"
KS_TOKEN_PRE="$KS_DIR/ks_token_"
KS_USER_PRE="$KS_DIR/ks_userid_"
KS_ROLE_PRE="$KS_DIR/ks_roleid_"
KS_TENANT_PRE="$KS_DIR/ks_tenantid_"
########################### function begin ##########################
ADMIN_USER=`echo $ADMIN_SETTING|cut -d"|" -f1`
ADMIN_PASS=`echo $ADMIN_SETTING|cut -d"|" -f2`
ADMIN_ROLE=`echo $ADMIN_SETTING|cut -d"|" -f3`
TENANT_NAME=`echo $ADMIN_SETTING|cut -d"|" -f4`

###
if [ `whoami` != "root" ]; then
	echo "You should be as root."
fi

env_initalize(){
### install kvm virtual software
#https://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse-4.noarch.rpm
yum -y install http://repos.fedorapeople.org/repos/openstack/openstack-icehouse/rdo-release-icehouse.rpm 
yum -y update

### install openstack software
yum --enablerepo=openstack-icehouse,epel -y install \
	qemu-kvm qemu-kvm-tools kvm virt-manager libvirt libvirt-python python-virtinst libvirt-client \
	iproute bridge-utils dnsmasq dnsmasq-utils avahi wget ntp ntpdate memcached httpd mod_wsgi mod_ssl \
	python-kombu python-anyjson python-pip python-tempita python-memcached tcpdump nc wget \
	rabbitmq-server scsi-target-utils iscsi-initiator-utils openvswitch \
	openstack-utils openstack-keystone openstack-glance openstack-nova openstack-cinder openstack-dashboard

###
hostname  $HOSTNAME
sed -r -i "s:HOSTNAME=.*:HOSTNAME=$HOSTNAME:g" /etc/sysconfig/network
sed -r -i "/$HOSTNAME/d" /etc/hosts
echo "$IPADDR	$HOSTNAME" >> /etc/hosts

sed -r -i 's:timeout=.*:timeout=5:' /boot/grub/menu.lst
grep -q "elevator=deadline" /boot/grub/menu.lst
[ $? = 0 ] || sed -r -i '/^[^#]kernel/s:(.*):\1 enforcing=0 highres=off elevator=deadline:' /boot/grub/menu.lst

echo 1 > /proc/sys/net/ipv4/ip_forward
sed -r -i '/ip_forward/d' /etc/rc.d/rc.local
echo "echo 1 > /proc/sys/net/ipv4/ip_forward" >> /etc/rc.d/rc.local
sed -r -i 's/^\s*#(net\.ipv4\.ip_forward=1.*)/\1/' /etc/sysctl.conf
 
### set timezone and language
grep -w -q $ZONE /etc/sysconfig/clock
if [ $? = 1 ];then
        sed -r -i "s:ZONE=.*:ZONE=\"$ZONE\":" /etc/sysconfig/clock
        cp -a /usr/share/zoneinfo/$ZONE /etc/localtime
fi

ntpdate -o3 $TIME_SRV

sed -r -i '/nofile/d' /etc/security/limits.conf
echo '* soft nofile 655350' >> /etc/security/limits.conf
echo '* hard nofile 655350' >> /etc/security/limits.conf
echo '#* soft memlock 104857' >> /etc/security/limits.conf
echo '#* hard memlock 104857' >> /etc/security/limits.conf

setenforce 0
sed -r -i '/^SELINUX=/s:.*:SELINUX=disabled:' /etc/sysconfig/selinux
sed -r -i '/^SELINUX=/s:.*:SELINUX=disabled:' /etc/selinux/config
###
#sed -r -i 's/#mdns_adv = 0/mdns_adv = 0/' /etc/libvirt/libvirtd.conf
#sed -r -i 's/#auth_unix_rw/auth_unix_rw/' /etc/libvirt/libvirtd.conf
sed -r -i 's:^#fudge:fudge:g' /etc/ntp.conf
sed -r -i 's:^#server.*127.127.1.0:server 127.127.1.0:g' /etc/ntp.conf

###
for svc in lvm2-monitor httpd mysqld libvirtd ntpd rabbitmq-server messagebus ntpd iptables memcached ksm ksmtuned tgtd;do
	chkconfig $svc on && service $svc stop && service $svc start
done

###
virsh net-autostart default --disable
virsh net-destroy default

cat > /etc/tgt/conf.d/cinder.conf <<EOF
include /var/lib/cinder/volumes/*
EOF

cat > /etc/tgt/targets.conf <<EOF
include /etc/tgt/conf.d/cinder.conf
default-driver iscsi
EOF
chkconfig tgtd on && service tgtd restart

###
rabbitmqctl change_password guest $PASSWD
}

keystone_init(){
openstack-db --init --service keystone --password $PASSWD

openssl rand -hex 10 > $KS_TOKEN_PRE$ADMIN_USER

cat > $KS_RCONFIG$ADMIN_USER <<EOF
export ADMIN_TOKEN=$(cat $KS_TOKEN_PRE$ADMIN_USER)
export OS_USERNAME=$ADMIN_USER
export OS_PASSWORD=$ADMIN_PASS
export OS_TENANT_NAME=$TENANT_NAME
export OS_AUTH_URL=http://$IPADDR:5000/v2.0/
export SERVICE_ENDPOINT=http://$IPADDR:35357/v2.0/
export SERVICE_TOKEN=$(cat $KS_TOKEN_PRE$ADMIN_USER)
EOF
source $KS_RCONFIG$ADMIN_USER
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $(cat $KS_TOKEN_PRE$ADMIN_USER)
sed -r -i '/OS_/d' ~/.bashrc
sed -r -i '/_TOKEN/d' ~/.bashrc
sed -r -i '/SERVICE_/d' ~/.bashrc
cat $KS_RCONFIG$ADMIN_USER >> ~/.bashrc
sed -r -i '/setenforce/d' ~/.bashrc
cat "setenforce 0" >> ~/.bashrc

keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
chkconfig openstack-keystone on && service openstack-keystone restart
sleep 5
 
echo $ADMIN_ROLE >> /tmp/sys_role
echo $TENANT_NAME >> /tmp/sys_tenant

for item in $SYSTEM_COMPONENT;do
	role=`echo $item|cut -d"|" -f3`	
	tenant=`echo $item|cut -d"|" -f4`	
	echo $role >> /tmp/sys_role
	echo $tenant >> /tmp/sys_tenant
done
echo "admin" >> /tmp/sys_role
echo "member" >> /tmp/sys_role
echo "admin" >> /tmp/sys_tenant
echo "service" >> /tmp/sys_tenant
ROLE=`sort -u /tmp/sys_role`
TENANT=`sort -u /tmp/sys_tenant`

for role in $ROLE;do
	printf "${GREEN_COL}%-15s\t${NORMAL_COL}" $role
	$COMMAND keys_addrole $role
done
echo

for tenant in $TENANT;do
	printf "${GREEN_COL}%-15s\t${NORMAL_COL}" $tenant
	$COMMAND keys_addtenant $tenant
done
echo

for item in "$ADMIN_USER|$ADMIN_PASS|$ADMIN_ROLE|$TENANT_NAME" $SYSTEM_COMPONENT;do
	user=`echo $item|cut -d"|" -f1`	
	pass=`echo $item|cut -d"|" -f2`	
	role=`echo $item|cut -d"|" -f3`	
	tenant=`echo $item|cut -d"|" -f4`	
	printf "${GREEN_COL}%-15s\t${NORMAL_COL}" $user
	$COMMAND keys_adduser $user $pass
	printf "${GREEN_COL}%15s\t${NORMAL_COL}" "------->"
	$COMMAND keys_bind $user $role $tenant
	echo
done
rm -rf /tmp/sys_*

### create default service
        $COMMAND keys_addsrv keystone identity 'OpenStack Identity Service'
	$COMMAND keys_addsrv nova compute 'OpenStack Compute Service'
        $COMMAND keys_addsrv glance image  'OpenStack Image Service'
        $COMMAND keys_addsrv cinder volume  'OpenStack Cinder Service'
#        $COMMAND keys_addsrv swift  object-store 'OpenStack Storage Service'
#        $COMMAND keys_addsrv ec2 ec2 'EC2 Service'

###
	$COMMAND keys_addept compute "http://$NOVA_URL"
	$COMMAND keys_addept image "http://$IMAGE_URL"
	$COMMAND keys_addept volume "http://$VOLUME_URL"
#	$COMMAND keys_addept object-store "http://$OBG_STORE_URL"
#	$COMMAND keys_addept ec2 "http://$EC2_URL"
	
	service_id=$(keystone service-list|awk -F'|' '/identity/{print $2}')
	keystone endpoint-create --region $REGION --service_id $service_id --publicurl http://$KEYS_URL --internalurl http://$KEYS_URL --adminurl http://$KEYS_ADMIN_URL
}

keystone_add_user(){
	if [ $# -ne 3 ];then
		echo "$SCRIPT keys_adduser user password"
	else
		user_name=$2
		user_pass=$3
		keystone user-create --name $user_name --pass $user_pass > $KS_USER_PRE$user_name
		user_id=$(awk -F'|' '/id/{print $3}' $KS_USER_PRE$user_name)
		echo -e "${YELLOW_COL}User added ID: $user_id ${NORMAL_COL}"
	fi
}

keystone_add_role(){
        if [ $# -ne 2 ];then
                echo "$SCRIPT keys_addrole role"
        else
                user_name=$2
                keystone role-create --name $user_name > $KS_ROLE_PRE$user_name
                role_id=$(awk -F'|' '/id/{print $3}' $KS_ROLE_PRE$user_name)
		echo -e "${YELLOW_COL}Role added ID: $role_id ${NORMAL_COL}"
        fi
}

keystone_add_tenant(){
        if [ $# -ne 2 ];then
                echo "$SCRIPT keys_addtenant tenant"
        else
                user_name=$2
                keystone tenant-create --name $user_name > $KS_TENANT_PRE$user_name
                tenant_id=$(awk -F'|' '/id/{print $3}' $KS_TENANT_PRE$user_name)
                echo -e "${YELLOW_COL}Tenant added ID: $tenant_id ${NORMAL_COL}"
        fi
}

keystone_list(){
        if [ $# -ne 2 ];then
                echo "$SCRIPT keys_list user|role|tenant|service|endpoint"
        else
                user_name=$2
		if [ $user_name = "all" ];then
			for i in user role tenant service;do
				echo -e "${YELLOW_COL}********************   $i List   ********************${NORMAL_COL}"
				keystone $i-list
				echo
			done
		else
			echo -e "${YELLOW_COL}********************   $user_name List   *********************${NORMAL_COL}"
                	keystone "$user_name"-list
		fi
        fi
}

keystone_user_role(){
       if [ $# -ne 4 ];then
                echo "$SCRIPT keys_bind user role tenant"
       else
                user_name=$2
                role_name=$3
		tenant_name=$4
		user_id=$(keystone user-list|awk -F'|' '/'"$user_name"'/{print $2}')
		role_id=$(keystone role-list|awk -F'|' '/'"$role_name"'/{print $2}')
		tenant_id=$(keystone tenant-list|awk -F'|' '/'"$tenant_name"'/{print $2}')
                STRING="keystone user-role-add \
                        --user-id $user_id \
                        --role-id $role_id \
                        --tenant_id $tenant_id "
                eval $STRING
		echo -e "${YELLOW_COL}User-Role-Tenant added successful.${NORMAL_COL}"
        fi

}

keystone_add_service(){
	if [ $# -ne 4 ];then
		echo "$SCRIPT keys_addsrv service type desc"
	else
		service_name=$2
		type=$3
		desc=$4
		keystone service-list|grep -q $service_name
		[ $? = 0 ] || keystone service-create --name $service_name --type $type --description "$desc"
	fi
}

keystone_add_endpoint(){
	if [ $# -ne 3 ];then
		echo "$SCRIPT keys_addept service url"
	else
		service_name=$2
		url=$3
		service_id=$(keystone service-list|awk -F'|' '/'"$service_name"'/{print $2}')
		STRING="keystone endpoint-create --region $REGION --service_id $service_id --publicurl '$url' --adminurl '$url' --internalurl '$url'"
		eval $STRING
	fi
}

glance_init(){
openstack-db --init --service glance --password $PASSWD

openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

openstack-config --set /etc/glance/glance-api.conf DEFAULT rabbit_userid guest
openstack-config --set /etc/glance/glance-api.conf DEFAULT rabbit_password $PASSWD

openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_token $(cat $KS_TOKEN_PRE$ADMIN_USER)
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_token $(cat $KS_TOKEN_PRE$ADMIN_USER)

cp /usr/share/glance/glance-api-dist-paste.ini /etc/glance/glance-api-paste.ini
cp /usr/share/glance/glance-registry-dist-paste.ini /etc/glance/glance-registry-paste.ini
chown -R root:glance /etc/glance/glance-api-paste.ini
chown -R root:glance /etc/glance/glance-registry-paste.ini

openstack-config --set /etc/glance/glance-api.conf paste_deploy config_file /etc/glance/glance-api-paste.ini
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-registry.conf paste_deploy config_file /etc/glance/glance-registry-paste.ini
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken auth_host $IPADDR
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_user glance
openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_password glance_secret
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken auth_host $IPADDR
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_user glance
openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_password glance_secret

for svc in registry api;do
	chkconfig openstack-glance-$svc on && service openstack-glance-$svc restart
done
}

glance_add_image(){
	if [ $# -ne 3 ];then
		echo "$SCRIPT gls_add image_desc image_filename"
	else
		desc="$2"
		filename=$3
		FORMAT="container_format=bare disk_format=raw"
		file $filename | grep -q -i 'qcow'
		[ $? = 0 ] && FORMAT="container_format=ovf disk_format=qcow2"
		file $filename | grep -q -i 'iso'
		[ $? = 0 ] && FORMAT="container_format=ovf disk_format=iso"
		STRING="glance add name=\"$desc\" is_public=true $FORMAT < $filename"
		eval $STRING
	fi
}

glance_list_image(){
	glance image-list
}

glance_show_image(){
	if [ $# -ne 2 ];then
		echo "$SCRIPT gls_show image_id"
	else
		glance image-show $2
	fi
}

nova_init(){
openstack-db --init --service nova --password $PASSWD

openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT connection_type libvirt
openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_type $VIRT_TYPE
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_userid guest
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_password $PASSWD

openstack-config --set /etc/nova/api-paste.ini filter:authtoken auth_host $IPADDR
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_tenant_name service
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_user nova
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_password nova_secret
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_token  $(cat $KS_TOKEN_PRE$ADMIN_USER)

nova_start
}

nova_to_control(){
	sed -r -i '/enabled_apis/d' /etc/nova/nova.conf
	for svc in `ls /etc/rc.d/init.d/openstack-*`;do
		svc=`basename $svc`
		echo $svc|grep -iqE "nova-compute|nova-metadata-api|nova-network"
		if [ $? = 0 ];then
			chkconfig $svc off && service $svc stop
		else
			chkconfig $svc on && service $svc start
		fi
	done
}

nova_to_compute(){
	sed -r -i '/enabled_apis/d' /etc/nova/nova.conf
	openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis metadata,ec2,osapi_compute
	for svc in `ls /etc/rc.d/init.d/openstack-*`;do
		svc=`basename $svc`
		echo $svc|grep -iqE "nova-compute|nova-metadata-api|nova-network"
		if [ $? = 0 ];then
			chkconfig $svc on && service $svc start
		else
			chkconfig $svc off && service $svc stop
		fi
	done
	for svc in httpd rabbitmq-server memcached mysqld;do
		chkconfig $svc off && service $svc stop
	done
}

nova_start(){
	for svc in novncproxy api conductor scheduler cert consoleauth; do
		chkconfig openstack-nova-$svc on && service openstack-nova-$svc start
	done 
}

nova_stop(){
	for svc in novncproxy api conductor scheduler cert consoleauth; do
		chkconfig openstack-nova-$svc on && service openstack-nova-$svc stop
	done 
}

nova_restart(){
	nova_stop
	nova_start
}

cinder_start(){
	for svc in api scheduler volume;do
		chkconfig openstack-cinder-$svc on && service openstack-cinder-$svc start
	done
}

cinder_stop(){
	for svc in api scheduler volume;do
		chkconfig openstack-cinder-$svc off && service openstack-cinder-$svc stop
	done
}

cinder_restart(){
	cinder_stop
	cinder_start
}

nova_show(){
	nova-manage service list
	nova flavor-list
	nova net-list
	nova-manage network list
	echo
	nova secgroup-list-rules default
	echo -e "${GREEN_COL}"
	nova keypair-list
	echo
	echo "+--------- Bridge Info ----------+"
	brctl show
	echo -e "${YELLOW_COL}"
	echo "+---------- IP Rules ------------+"
	ip ru
	echo
	echo "+---------- IP Route ------------+"
	ip ro
	echo
	echo -en ${NORMAL_COL}
}

nova_create_keypair(){
	KEY=$2
	[ -z $KEY ] && KEY=$KEYPAIR
	KEY="_"$KEY
	rm -rf $KEY.*
	nova keypair-add $KEY > $KEY.key
	chmod 600 $KEY.key
	openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_inject_partition -1
	openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_inject_password False
}

nova_create_network(){
	nova network-create testnet --bridge br100 --multi-host T --fixed-range-v4 10.10.10.0/24 --dns1 8.8.8.8 --dns2 114.114.114.114 --gateway 10.10.10.1
	#nova-manage floating create --ip_range=192.168.13.128/27  --pool public_ip
}

swift_init(){
#dd if=/dev/zero of=/var/lib/nova/swift-volumes.img bs=1M seek=1k count=0
#mkfs.xfs -i size=1024 /var/lib/nova/swift-volumes.img
#mount -t xfs -o loop,defaults,noatime,nodiratime,nobarrier,logbufs=8 0 0 to /etc/fstab
#LOOP_DEV=$(losetup -a|awk -F: '/swift-volumes/{split($1,dev,"/")} {print dev[3]}')
LOOP_DEV="sdb2"

rm -rf /etc/rsyncd.conf
rm -rf /etc/swift/swift_ring.sh
rm -rf /etc/swift/account-server.conf
rm -rf /etc/swift/account-server/*.conf
rm -rf /etc/swift/container-server.conf
rm -rf /etc/swift/container-server/*.conf
rm -rf /etc/swift/object-server.conf
rm -rf /etc/swift/object-server/*.conf
rm -rf /etc/swift/*.gz
rm -rf /etc/swift/backups/*
rm -rf /mnt/swift/node*
rm -rf /srv/node*

cat > /etc/swift/swift_ring.sh <<EOF
swift-ring-builder object.builder create 18 3 1
swift-ring-builder container.builder create 18 3 1
swift-ring-builder account.builder create 18 3 1
EOF

cat > /etc/rsyncd.conf <<EOF
# General stuff
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = $IPADDR
EOF

for x in {1..3};do
	i=`printf "%03d" $x`
	mkdir -p /mnt/swift/node$i
	ln -snf /mnt/swift/node$i /srv/
	chown -R swift.swift /mnt/swift
	chown -R swift.swift /srv

cat >> /etc/rsyncd.conf <<EOF

# Account Server replication settings
[account6$i]
max connections = 25
path = /srv/node$i/
read only = false
lock file = /var/lock/account6$i.lock

# Container server replication settings
[container6$i]
max connections = 25
path = /srv/node$i/
read only = false
lock file = /var/lock/container6$i.lock

# Object Server replication settings
[object6$i]
max connections = 25
path = /srv/node$i/
read only = false
lock file = /var/lock/object6$i.lock
############################################
EOF

############################################
cat > /etc/swift/account-server/$i.conf <<EOF
[DEFAULT]
devices = /srv/node$i
mount_check = false
bind_ip = 0.0.0.0
bind_port = 6$i
workers = 3
user = swift
log_facility = LOG_LOCAL1
 
[pipeline:main]
pipeline = account-server

[app:account-server]
use = egg:swift#account
 
[account-replicator]
vm_test_mode = no

[account-auditor]

[account-reaper]
EOF
echo "swift-ring-builder account.builder add z$i-$IPADDR:6${i}/$LOOP_DEV 100" >> /etc/swift/swift_ring.sh

cat >/etc/swift/container-server/$i.conf <<EOF
[DEFAULT]
devices = /srv/node$i
mount_check = false
bind_ip = 0.0.0.0
bind_port = 6$i
workers = 3
user = swift
log_facility = LOG_LOCAL2

[pipeline:main]
pipeline = container-server

[app:container-server]
use = egg:swift#container

[container-replicator]
vm_test_mode = no

[container-updater]

[container-auditor]

[container-sync]
EOF
echo "swift-ring-builder container.builder add z$i-$IPADDR:6${i}/$LOOP_DEV 100" >> /etc/swift/swift_ring.sh

cat > /etc/swift/object-server/$i.conf <<EOF
[DEFAULT]
devices = /srv/node$i
mount_check = false
bind_ip = 0.0.0.0
bind_port = 6$i
workers = 3
user = swift
log_facility = LOG_LOCAL3

[pipeline:main]
pipeline = object-server

[app:object-server]
use = egg:swift#object

[object-replicator]
vm_test_mode = no

[object-updater]

[object-auditor]
EOF
echo "swift-ring-builder object.builder add z$i-$IPADDR:6${i}/$LOOP_DEV 100" >> /etc/swift/swift_ring.sh
cat <<EOF >>/etc/swift/container-server.conf 
[container-sync]
EOF
done
cat >> /etc/swift/swift_ring.sh <<EOF

swift-ring-builder account.builder rebalance
swift-ring-builder container.builder rebalance
swift-ring-builder object.builder rebalance
EOF
############################################
sed -r -i "/disable/s:.*:\tdisable = no:g" /etc/xinetd.d/rsync
mkdir -p /var/log/swift
chown -R swift.root /var/log/swift
cat > /etc/rsyslog.d/10-swift.conf << EOF
local0.*   /var/log/swift/proxy.log
local1.*   /var/log/swift/account.log
local2.*   /var/log/swift/container.log
local3.*   /var/log/swift/object.log
EOF

openstack-config --set /etc/swift/swift.conf swift-hash swift_hash_path_suffix $(od -t x8 -N 8 -A n </dev/random)
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken admin_token $(cat $KS_TOKEN_PRE$ADMIN_USER)
openstack-config --set /etc/swift/proxy-server.conf filter:authtoken auth_token $(cat $KS_TOKEN_PRE$ADMIN_USER)
openstack-config --set /etc/swift/proxy-server.conf filter:keystone operator_roles "member,admin"
openstack-config --set /etc/swift/proxy-server.conf DEFAULT log_level "DEBUG"
openstack-config --set /etc/swift/proxy-server.conf DEFAULT log_facility "LOG_LOCAL0"
openstack-config --set /etc/swift/proxy-server.conf DEFAULT workers "3"

cd /etc/swift
chmod a+x /etc/swift/swift_ring.sh
./swift_ring.sh
cd -

for svc in account container object proxy;do
	chkconfig openstack-swift-$svc on && service openstack-swift-$svc restart
done
	chkconfig memcached on && service memcached restart
}

swift_start(){
for svc in account container object proxy;do
	chkconfig openstack-swift-$svc on && service openstack-swift-$svc start
done
}

swift_stop(){
for svc in account container object proxy;do
	chkconfig openstack-swift-$svc off && service openstack-swift-$svc stop
done
}

swift_check(){
	cd /etc/swift
	for i in account container object;do
		swift-ring-builder $i.builder
		echo '------------------------------------'
	done
	cd -
}

cinder_init(){
openstack-db --init --service cinder --password $PASSWD

openstack-config --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone

openstack-config --set /etc/cinder/cinder.conf keymgr auth_uri http://$IPADDR:5000
openstack-config --set /etc/cinder/cinder.conf keymgr auth_url http://$IPADDR:35357
openstack-config --set /etc/cinder/cinder.conf keymgr auth_uri identity_uri http://$IPADDR:35357
openstack-config --set /etc/cinder/cinder.conf keymgr admin_user cinder
openstack-config --set /etc/cinder/cinder.conf keymgr admin_password cinder_secret
openstack-config --set /etc/cinder/cinder.conf keymgr admin_tenant_name service

openstack-config --set /etc/cinder/cinder.conf DEFAULT rpc_backend rabbit
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_host $IPADDR
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_port 5672
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_userid guest
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_password $PASSWD

openstack-config --set /etc/cinder/cinder.conf DEFAULT glance_host $IPADDR
openstack-config --set /etc/cinder/cinder.conf DEFAULT iscsi_helper tgtadm
openstack-config --set /etc/cinder/cinder.conf DEFAULT volume_group cinder-volumes
openstack-config --set /etc/cinder/cinder.conf DEFAULT state_path /var/lib/cinder
openstack-config --set /etc/cinder/cinder.conf DEFAULT volumes_dir /var/lib/cinder/volumes

openstack-config --set /etc/cinder/cinder.conf database connection mysql://cinder:$PASSWD@$IPADDR/cinder

mkdir -p /var/lib/cinder/volumes
chown -R cinder.cinder /var/lib/cinder/volumes

for svc in api scheduler volume;do
        chkconfig openstack-cinder-$svc on && service openstack-cinder-$svc restart
done
}

case $1 in
	env_initalize)
		env_initalize;;
	keys_init)
		keystone_init;;
	keys_adduser)
		keystone_add_user "$@";;
	keys_addtenant)
		keystone_add_tenant "$@";;
	keys_addrole)
		keystone_add_role "$@";;
	keys_addsrv)
		keystone_add_service "$@";;
	keys_addept)
		keystone_add_endpoint "$@";;
	keys_list)
		keystone_list "$@";;
	keys_bind)
		keystone_user_role "$@";;
	gls_init)
		glance_init;;
	gls_add)
		glance_add_image "$@";;
	gls_show)
		glance_show_image "$@";;
	gls_list)
		glance_list_image;;
	nova_init)
		nova_init;;
	nova_start)
		nova_start;;
	nova_stop)
		nova_stop;;
	nova_restart)
		nova_restart;;
	nova_check)
		nova_show;;
	nova_network)
		nova_network;;
	nova_addkey)
		nova_create_keypair "$@";;
	nova_addnet)
		nova_create_network;;
	nova_to_control)
		nova_to_control;;
	nova_to_compute)
		nova_to_compute;;
        swift_init)
                swift_init;;
	swift_start)
		swift_start;;
	swift_stop)
		swift_stop;;
        swift_check)
                swift_check;;
	cinder_init)
		cinder_init;;
	cinder_stop)
		cinder_stop;;
	cinder_start)
		cinder_start;;
	cinder_restart)
		cinder_restart;;
	*)
		echo -e "${RED_COL}$SCRIPT ${YELLOW_COL}env_initalize"
		echo -e "${RED_COL}$SCRIPT ${GREEN_COL}keys_init|keys_adduser|keys_addtenant|keys_addrole|keys_addsrv|keys_addept|keys_bind|keys_list"
		echo -e "${RED_COL}$SCRIPT ${GREEN_COL}gls_init|gls_add|gls_show|gls_list"
		echo -e "${RED_COL}$SCRIPT ${GREEN_COL}nova_init|nova_to_control|nova_to_compute|nova_start|nova_stop|nova_restart|nova_addkey|nova_addnet|nova_check"
		echo -e "${RED_COL}$SCRIPT ${GREEN_COL}cinder_init|cinder_stop|cinder_start|cinder_restart|cinder_check"
                echo -e "${RED_COL}$SCRIPT ${GREEN_COL}swift_init|swift_start|swift_stop|swift_check"
		echo -en ${NORMAL_COL}
esac
