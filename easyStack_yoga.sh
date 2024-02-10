#!/bin/sh
MY_IP=$(ip a | awk '/inet.*internal/{split($2,a,"/");{if(a[1]!="127.0.0.1") print a[1]}}'|head -1)
REGION="Region0571"
DBPASSWD="***upyun***"
DBROOTPW="***upyun***"
DEBUG="True"
##############################################
CCVIP=$MY_IP
readonly ZONE="Asia/Shanghai"
readonly VERSION="yoga"
readonly CPU_RATIO=10
readonly MEM_RATIO=1.5
readonly MY_UUID="9a3b92a-4f84-34gh-89zv-7de9346qwxr"
readonly CPU_NUMS=`grep -c "vendor_id" /proc/cpuinfo`
# 配置颜色
readonly RED_COL="\\033[1;31m"	    # red color
readonly GREEN_COL="\\033[32;1m"     # green color
readonly BLUE_COL="\\033[34;1m"	    # blue color
readonly YELLOW_COL="\\033[33;1m"    # yellow color
readonly NORMAL_COL="\\033[0;39m"
readonly MY_PORT=3306

# 如果不是root，就退出
if [ `whoami` != "root" ]; then
  echo "You should be as root."
  exit 0
fi

grep -wEq "vmx|svm" /proc/cpuinfo
if [ $? = 0 ];then
  lsmod |grep -qw kvm
  [ $? = 0 ] && VIRT_TYPE="kvm"
fi
##############################################
check_env(){
if [ ! -s ~/.easystackrc ];then
    echo -en "Input Host Name ${YELLOW_COL} [ $(hostname) ] ${NORMAL_COL}: " && read VARIABLE
    [ ! -z "$VARIABLE" ] && HOSTNAME=$VARIABLE
    
    echo -en "Input Region No ${YELLOW_COL} [ $REGION ] ${NORMAL_COL}: " && read VARIABLE
    [ ! -z "$VARIABLE" ] && REGION=$VARIABLE
    
    echo -en "Input Local IP ${YELLOW_COL} [ $MY_IP ] ${NORMAL_COL}: " && read VARIABLE
    if [ ! -z "$VARIABLE" ];then
      VALID_CHECK=$(echo $VARIABLE|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
      if [ ! -z $VALID_CHECK ] && [ $VALID_CHECK = "yes" ];then
        MY_IP=$VARIABLE
      else
        echo "IP Format Error!" && exit 0
      fi
    fi
    
    echo -en "Does it MySQL Cluster? ${YELLOW_COL} [ Y|N ] ${NORMAL_COL}: " && read -n 1 VARIABLE
    if [ ! -z ${VARIABLE} ] && [ ${VARIABLE,,} = "y" ];then
      i=1
      while [ $i -le 3 ];do
	echo -en "\n${YELLOW_COL}$i node ip address${NORMAL_COL}: " && read VARIABLE
	  if [ ! -z "$VARIABLE" ];then
	    VALID_CHECK=$(echo $VARIABLE|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
	    if [ ! -z $VALID_CHECK ] && [ $VALID_CHECK = "yes" ];then
	      GLERA_SRV+="$VARIABLE,"
	      ((i++))
	    else
	      echo "IP Format error!"
	    fi
	  fi
      done
      GLERA_SRV=${GLERA_SRV%,}
    else
      echo -en "\nCompute Node."
      GLERA_SRV=
    fi
    echo

    echo -en "Input Provider Device ${YELLOW_COL} [ $PROVIDER_INTERFACE ] ${NORMAL_COL}: \n"
    A_LISTS=$(ip a | awk '/LOWER_UP/{if($2~/(e|b)(t|m|n|o)/){gsub(":","",$2);print $2}}')
    select choice in $A_LISTS; do
      if [ ! -z $choice ];then
        PROVIDER_INTERFACE=$choice
        break
      fi
    done
    
    echo -en "Input Storage Backend ${YELLOW_COL} [ $STORE_BACKEND ] ${NORMAL_COL}: \n"
    A_LISTS="LVM Ceph"
    select choice in $A_LISTS; do
      if [ ! -z $choice ];then
        STORE_BACKEND=${choice,,}
        break
      fi
    done
    
    echo -en "Choos Node Role ${YELLOW_COL} [ $NODE_TYPE ] ${NORMAL_COL}: \n"
    A_LISTS="ALL Control Network Compute"
    select choice in $A_LISTS; do
       case $choice in
         ALL)
          NODE_TYPE="all"
          break;;
         Control)
          NODE_TYPE="control"
          break;;
         Network)
          NODE_TYPE="network"
          break;;
         Compute)
          NODE_TYPE="compute"
          break;;
         *)
          echo "Choose again ";;
       esac
    done
    
    GPUNAME=$(lspci -nn| sed -r -n '/VGA.*NVIDIA/s@.*\[(.*)\].*\[.*@\1@gp'|tr ' ' '_'|sort -u)
    echo $GPUNAME | grep -iq ^[a-zA-Z]
    if [ $? = 1 ];then
      echo -en "Input GPU Name${YELLOW_COL} [ $GPUNAME ] ${NORMAL_COL}: " && read VARIABLE
      [ ! -z "$VARIABLE" ] && GPUNAME=$VARIABLE
    fi


    CCVIP=`echo $HOSTNAME|awk -F. '{print "cc."$(NF-1)"."$NF}'`
    DBVIP=`echo $HOSTNAME|awk -F. '{print "db."$(NF-1)"."$NF}'`
    cat > ~/.easystackrc <<EOF
HOSTNAME="$HOSTNAME"
NODE_TYPE="$NODE_TYPE"
REGION="$REGION"
CCVIP="$CCVIP"
DBVIP="$DBVIP"
MY_IP="$MY_IP"
VIRT_TYPE="${VIRT_TYPE:-"qemu"}"
PROVIDER_INTERFACE="$PROVIDER_INTERFACE"
GLERA_SRV="${GLERA_SRV%,}"
MEMCACHES="$CCVIP:11211"
STORE_BACKEND=$STORE_BACKEND
GPUNAME="${GPUNAME,,}"

NOVA_URL="http://$CCVIP:8774/v2.1"
IMAGE_URL="http://$CCVIP:9292/v2"
VOLUME_URL="http://$CCVIP:8776/v3"
NEUTRON_URL="http://$CCVIP:9696"
OCTAVIA_URL="http://$CCVIP:9876"
PLACEMENT_URL="http://$CCVIP:8778"
KEYS_AUTH_URL="http://$CCVIP:5000/v3"
KEYS_ADMIN_URL="http://$CCVIP:35357/v3"
EOF
fi
  ##############################################
  echo -en "${GREEN_COL}-------------- Individual Parameters ---------------${NORMAL_COL}\n"
    cat ~/.easystackrc
  grep -iq $VERSION /etc/yum.repos.d/ -r -l
  if [ $? = 0 ];then
    echo -en "${YELLOW_COL}----------------   Are you sure?   -----------------${NORMAL_COL}\n\n"
  else
    echo -en "\n${GREEN_COL}=========  $0 ${YELLOW_COL}adjust_sys ${GREEN_COL} =========${NORMAL_COL}\n\n"
    exit 0
  fi
}
##############################################
readonly ADMIN_SETTING="admin|XXX|admin|service" #  user|pass|role|tenant
readonly SCRIPT="easyStack_$VERSION.sh"
readonly COMMAND=`pwd`"/$SCRIPT"
# 配置参数保存目录
readonly KS_DIR="/var/lib/keystone"
readonly KS_RCONFIG="$KS_DIR/ks_rc_"
readonly KS_TOKEN_PRE="$KS_DIR/ks_token_"
readonly KS_USER_PRE="$KS_DIR/ks_userid_"
readonly KS_ROLE_PRE="$KS_DIR/ks_roleid_"
readonly KS_SERV_PRE="$KS_DIR/ks_servid_"
readonly KS_TENANT_PRE="$KS_DIR/ks_tenantid_"
############## function begin #################
ADMIN_USER=`echo $ADMIN_SETTING|cut -d"|" -f1`
#ADMIN_PASS=`echo "$ADMIN_USER@@$DBPASSWD" | md5sum | cut -c1-15`
ADMIN_PASS="$ADMIN_USER@$DBPASSWD"
ADMIN_ROLE=`echo $ADMIN_SETTING|cut -d"|" -f3`
TENANT_NAME=`echo $ADMIN_SETTING|cut -d"|" -f4`

# 导入 admin凭证
[ -s $KS_RCONFIG$ADMIN_USER ] && source $KS_RCONFIG$ADMIN_USER
[ -s ~/.easystackrc ] && source ~/.easystackrc

adjust_sys(){
# 禁用SELinux
  echo -en "${YELLOW_COL}----------------  Check SELinux/Firewall/Repo/Yoga  -----------------${NORMAL_COL}\n\n"
  setenforce 0
  grubby --update-kernel ALL --args selinux=0
  sed -r -i '/^SELINUX=/s:.*:SELINUX=disabled:' /etc/sysconfig/selinux
  sed -r -i '/^SELINUX=/s:.*:SELINUX=disabled:' /etc/selinux/config
  sed -i -e "s|mirrorlist=|#mirrorlist=|g" /etc/yum.repos.d/CentOS-*
  sed -i -e "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
  sed -i -e "s|#baseurl=http://mirrorlist.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*
  dnf install -y epel-release.noarch

# 安装rdo仓库
  grep -iq $VERSION /etc/yum.repos.d/ -r -l
  if [ $? != 0 ];then
    dnf install -y https://repos.fedorapeople.org/repos/openstack/openstack-yoga/rdo-release-yoga-1.el8.noarch.rpm
  fi
  dnf install -y python3-openstackclient python3-libvirt libvirt tar rsyslog supervisor pciutils chrony screen bind-utils --enablerepo=epel     

# 配置主机名
  sed -r -i "/$HOSTNAME/d" /etc/hosts
  echo -en "$MY_IP \t $HOSTNAME\n" >> /etc/hosts
  hostnamectl --static set-hostname $HOSTNAME
  hostnamectl --pretty set-hostname $HOSTNAME
  hostnamectl --transient set-hostname $HOSTNAME
  echo "$HOSTNAME" > /proc/sys/kernel/hostname
  if [ -s /network.info ];then
    sed -r -i '/^HOSTNAME/d' /network.info
    sed -r -i "1i HOSTNAME=\"$HOSTNAME\"" /network.info
  fi

# 配置ssh的密钥访问
  cat > ~/.ssh/config <<EOF
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
User root
Port 22
Identityfile ~/.ssh/id_rsa
EOF

# 配置终端字符集
  localectl set-locale LANG=en_US.UTF8
  cat > /etc/locale.conf <<EOF
LANG=en_US.utf8
LC_CTYPE=en_US.utf8
EOF

  sed -r -i '/nofile/d' /etc/security/limits.conf
  cat > /etc/security/limits.d/20-nproc.conf  <<EOF
*          soft    nproc    10240
root       soft    nproc    unlimited
EOF

  cat >> /etc/dnf/dnf.conf <<EOF
# 禁用 automatic updates
automatic_config=false
automatic_upgrade=false
EOF

### set timezone and language
  ln -snf /usr/share/zoneinfo/$ZONE /etc/localtime
  timedatectl set-timezone $ZONE
  timedatectl set-ntp 1
  timedatectl set-local-rtc 0
  chronyc makestep
  
  sed -r -i -e '/DefaultLimitCORE/s^.*^DefaultLimitCORE=infinity^g' \
            -e '/DefaultLimitNOFILE/s^.*^DefaultLimitNOFILE=100000^g' \
	    -e '/DefaultLimitNPROC/s^.*^DefaultLimitNPROC=100000^g' /etc/systemd/system.conf
  sed -r -i -e 's@weekly@daily@g;s@^rotate.*@rotate 7@g;s@^#compress.*@compress@g' /etc/logrotate.conf
  sed -r -i -e '/Compress=/s@.*@Compress=yes@g; /SystemMaxUse=/s@.*@SystemMaxUse=4G@g; ' \
            -e '/SystemMaxFileSize=/s@.*@SystemMaxFileSize=256M@g; ' \
	    -e '/MaxRetentionSec=/s@.*@MaxRetentionSec=2week@g' /etc/systemd/journald.conf
  
  grep MAILTO= /etc/ -r -l | xargs sed -r -i '/MAILTO=/s@=.*@=@'
  sed -r -i '/^CRONDARGS=/s@=.*@="-s -m off"@g' /etc/sysconfig/crond
  
  systemctl disable --now rpcbind.target rpcbind.service rpcbind.socket firewalld postfix irqbalance tuned sssd
# 固定版本yum-versionlock
  POWERTOOLS=$(grep -i '\[powertools\]' /etc/yum.repos.d/*.repo | sed -r -n 's@.*\[(.*)\].*@\1@gp'|sort -u|head -1)
  dnf config-manager --set-disabled epel
  dnf config-manager --set-enabled $POWERTOOLS

# 开启透明大页
  cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF
  echo always > /sys/kernel/mm/transparent_hugepage/enabled
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
  echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/defrag
}

# 安装openstack控制器组件
control_init(){
  POWERTOOLS=$(grep -i '\[powertools\]' /etc/yum.repos.d/*.repo | sed -r -n 's@.*\[(.*)\].*@\1@gp'|sort -u|head -1)

  grep -iq $VERSION /etc/yum.repos.d/ -r -l
  if [ $? != 0 ] ;then
    dnf -y install https://repos.fedorapeople.org/repos/openstack/openstack-yoga/rdo-release-yoga-1.el8.noarch.rpm
  fi
  
  for svc in httpd mariadb-server rabbitmq-server memcached nginx-mod-stream haproxy mod_ssl ebtables bridge-utils ipset python3-mod_wsgi python3-oauth2client python3-openstackclient ;do
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc 
    [ $? != 0 ] && dnf --enablerepo=$POWERTOOLS --enablerepo=openstack-$VERSION install -y $svc
  done
  
  if [ ! -z "$GLERA_SRV" ];then
    echo -e "${YELLOW_COL}-> Installing MariaDB Glera Cluster ... ${NORMAL_COL}"
    dnf list installed | grep -iq mariadb-server-galera
    [ $? != 0 ] && dnf --enablerepo=$POWERTOOLS --enablerepo=openstack-$VERSION install -y mariadb-server-galera

    if [ -s /etc/my.cnf.d/galera.cnf ];then
      sed -r -i '/shy_begin/, /shy_end/d' /etc/my.cnf.d/galera.cnf
      sed -r -i "/^wsrep_provider/a ### shy_begin\nwsrep_provider_options=\"gmcast.listen_addr=tcp://$MY_IP:4567; gcs.fc_limit = 2048; gcs.fc_factor = 0.99; gcs.fc_master_slave = yes\"\nbind-address=\"$MY_IP\"\nwsrep_cluster_name=\"yoga_wsrep_db\"\nwsrep_cluster_address=\"gcomm://$GLERA_SRV\"\nwsrep_node_address=\"$MY_IP\"\nwsrep_slave_threads = 300\n### shy_end" /etc/my.cnf.d/galera.cnf
    fi
  fi

  sed -r -i '/auth_gssapi.so/s@^@#@g' /etc/my.cnf.d/auth_gssapi.cnf
  if [ -s /etc/my.cnf.d/mariadb-server.cnf ];then
    sed -r -i '/shy_begin/, /shy_end/d' /etc/my.cnf.d/mariadb-server.cnf
    sed -r -i "/pid-file/a ### shy_begin\ndefault-storage-engine = innodb\ninnodb_file_per_table = on\nback_log = 10240\nmax_connections = 10240\nthread_cache_size = 10240\nmax_connect_errors = 10240\nthread_pool_idle_timeout = 7200\nconnect_timeout = 7200\nnet_read_timeout = 7200\nnet_write_timeout = 7200\ninteractive_timeout = 7200\nwait_timeout = 7200\nhost_cache_size = 0\nthread_pool_size = 1024\nquery_cache_size = 512M\nmax_allowed_packet = 512M\nnet_buffer_length = 1048576\ncollation-server = utf8_general_ci\ncharacter-set-server = utf8\nbind-address = $MY_IP\nport = $MY_PORT\n### shy_end" /etc/my.cnf.d/mariadb-server.cnf
  fi

  if [ -s /etc/sysconfig/memcached ];then
cat >/etc/sysconfig/memcached <<EOF
PORT="11211"
USER="memcached"
MAXCONN="4096"
CACHESIZE="256"
OPTIONS="-l $MY_IP"
EOF
  fi

  if [ -s /etc/rabbitmq/rabbitmq.conf ];then
    sed -r -i -e "/management.tcp.ip/s@.*@management.tcp.ip = $MY_IP@g" \
	-e "/listeners.tcp.local /s@.*@listeners.tcp.local = $MY_IP:5672@g" /etc/rabbitmq/rabbitmq.conf
    cat > /etc/rabbitmq/rabbitmq-env.conf<<EOF
RABBITMQ_NODE_IP_ADDRESS=$MY_IP
export ERL_EPMD_ADDRESS=$MY_IP
EOF
  fi

  cat > /etc/nginx/nginx.conf <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 10240;
}

EOF
  cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     10240
    user        haproxy
    group       haproxy
    daemon

defaults
    mode                    tcp
    log                     global
    retries                 10
    timeout queue           10m
    timeout connect         10m
    timeout check           30s

EOF

  for svc in rabbitmq-server mariadb memcached ;do
    echo -e "${YELLOW_COL} ->  Starting Service $svc ... ${NORMAL_COL}"
    systemctl enable --now $svc
  done

  #scp /var/lib/rabbitmq/.erlang.cookie node:/var/lib/rabbitmq/.erlang.cookie
  #rabbitmqctl stop_app
  #rabbitmqctl reset
  #rabbitmqctl forget_cluster_node ccm-01
  #rabbitmqctl join_cluster rabbit@ccm-01
  #rabbitmqctl start_app
  rabbitmqctl change_password guest $DBPASSWD
  rabbitmqctl set_permissions guest ".*" ".*" ".*"
  rabbitmq-plugins enable rabbitmq_management
  
  # grant all privileges on *.* to root@'100.100.%' identified by 'DBROOTPW' with grant option
  echo -e "${YELLOW_COL} MySQL-> UPDATE user SET Password=PASSWORD(\"DBROOTPW\") WHERE User=\"root\"${NORMAL_COL}"
}

env_clean(){
  echo -e "${YELLOW_COL}Neutron: Clean unused agent... ${NORMAL_COL}"
  #openstack network agent list | awk '/XXX/{print $2}'|xargs -i openstack network agent delete {}
  SRV=$(neutron agent-list | awk -v ORS=" " '/xxx/{print $2}')
  [ -z "$SRV" ] || neutron agent-delete $SRV

  echo -e "${YELLOW_COL}Compute: Clean unused nova agent... ${NORMAL_COL}"
  #openstack compute service list | awk '/down/{print $2}'|xargs -i openstack compute service delete {}
  SRV=$(openstack compute service list|awk -v ORS=" " '/down/{print $2}')
  [ -z "$SRV" ] || openstack compute service delete $SRV

  echo -e "${YELLOW_COL}Another function is not yet implemented ${NORMAL_COL}"
}

keystone_init(){
  echo -e "${YELLOW_COL}Install KeyStone Identity v3${NORMAL_COL}"
  for svc in keystone dashboard;do
    svc="openstack-$svc"
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc
    [ $? != 0 ] && dnf install -y $svc
  done

  openssl rand -hex 10 > $KS_TOKEN_PRE$ADMIN_USER
  mysql -uroot -p"$DBROOTPW" -e 'CREATE DATABASE IF NOT EXISTS keystone;'
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  if [ -z "$GLERA_SRV" ];then
    MEM_LOCAT="$MY_IP:11211"
  else
    MEM_LOCAT=$(echo $GLERA_SRV|awk -F, '{print $1":11211,"$2":11211,"$3":11211"}')
  fi
  cat > /etc/keystone/keystone.conf <<EOF
[DEFAULT]

[database]
connection = mysql+pymysql://keystone:$DBPASSWD@$DBVIP:$MY_PORT/keystone

[cache]
backend = oslo_cache.memcache_pool
enabled = true
memcache_servers = $MEM_LOCAT

[token]
provider = fernet
EOF

if [ $(ls -al /var/lib/mysql/keystone/* | wc -l) -lt 10 ];then
  su -s /bin/sh -c "keystone-manage db_sync" keystone

  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
  keystone-manage bootstrap --bootstrap-service-name keystone --bootstrap-username admin --bootstrap-role-name admin \
    --bootstrap-admin-url $KEYS_ADMIN_URL --bootstrap-internal-url $KEYS_AUTH_URL --bootstrap-public-url $KEYS_AUTH_URL \
    --bootstrap-password $ADMIN_PASS --bootstrap-region-id $REGION --bootstrap-project-name $TENANT_NAME
fi

  sed -r -i '/ServerName /d' /etc/httpd/conf/httpd.conf
  sed -r -i "/^Listen/s@.*@Listen $MY_IP:8000@g" /etc/httpd/conf/httpd.conf
  mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.old
  echo "ServerName $CCVIP" >> /etc/httpd/conf/httpd.conf
  > /var/www/html/index.html

  sed -r -i '/WSGIApplicationGroup/d' /etc/httpd/conf.d/openstack-dashboard.conf
  sed -r -i -e '/WSGISocketPrefix/a WSGIApplicationGroup %{GLOBAL}' -e 's@dashboard/wsgi>@dashboard>@g' \
  -e '/^WSGIScriptAlias/s^.*^WSGIScriptAlias /dashboard /usr/share/openstack-dashboard/openstack_dashboard/wsgi.py^g' \
	  /etc/httpd/conf.d/openstack-dashboard.conf

  sed -r -i "/^ALLOWED_HOSTS/s^.*^ALLOWED_HOSTS = ['*',]^g" /etc/openstack-dashboard/local_settings
  sed -r -i "/^OPENSTACK_HOST/s^.*^OPENSTACK_HOST = \"$CCVIP\"^g" /etc/openstack-dashboard/local_settings
  sed -r -i "/^TIME_ZONE/s^.*^TIME_ZONE = \"$ZONE\"^g" /etc/openstack-dashboard/local_settings
  sed -r -i "/^OPENSTACK_KEYSTONE_URL/s^=.*^= \"$KEYS_AUTH_URL\"^g" /etc/openstack-dashboard/local_settings
  sed -r -i -e '/WEBROOT/d' -e '/LOGIN_URL/d' -e '/LOGOUT_URL/d' -e '/LOGIN_REDIRECT_URL/d' \
	    -e '/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN/d' -e '/^OPENSTACK_API_VERSIONS /d' \
	    -e '/^CACHES/d' -e '/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT/d' \
	  /etc/openstack-dashboard/local_settings

  cat >>  /etc/openstack-dashboard/local_settings <<EOF
WEBROOT = '/dashboard/'
LOGIN_URL = '/dashboard/auth/login/'
LOGOUT_URL = '/dashboard/auth/logout/'
LOGIN_REDIRECT_URL = '/dashboard/'
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'Default'
OPENSTACK_API_VERSIONS = { "identity": 3, "volume": 3, "compute": 2, "image":2 }
CACHES = { 'default': { 'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache', 'LOCATION': '$MEMCACHES', }, }
EOF

  [ -L /etc/httpd/conf.d/wsgi-keystone.conf ] && rm -rf /etc/httpd/conf.d/wsgi-keystone.conf
  cp -a /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/wsgi-keystone.conf
  sed -r -i "/Listen/s@(.*) (.*)@\1 $MY_IP:\2@g" /etc/httpd/conf.d/wsgi-keystone.conf
  cp -a /etc/httpd/conf.d/wsgi-keystone.conf /etc/httpd/conf.d/wsgi-keystone-admin.conf
  sed -r -i 's@5000@35357@g;s@-public@-admin@g' /etc/httpd/conf.d/wsgi-keystone-admin.conf
  systemctl enable httpd && systemctl restart httpd 

  cat > $KS_RCONFIG$ADMIN_USER <<EOF
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
export OS_PROJECT_NAME=$TENANT_NAME
export OS_USERNAME=$ADMIN_USER
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=$KEYS_AUTH_URL
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export OS_VOLUME_API_VERSION=3
EOF
  sed -r -i '/OS_/d' ~/.bashrc
  sed -r -i '/_TOKEN/d' ~/.bashrc
  sed -r -i '/SERVICE_/d' ~/.bashrc
  cat $KS_RCONFIG$ADMIN_USER >> ~/.bashrc

  source $KS_RCONFIG$ADMIN_USER
  $COMMAND keys_addproj $TENANT_NAME
}

keystone_add_proj(){
  if [ $# -ne 2 ];then
    echo "$SCRIPT keys_addproj project"
  else
    proj_name=$2
    openstack project list | grep -wq "$proj_name"
    if [ $? != 0 ] ;then
      openstack project create --domain default --description "Service Project" $proj_name > $KS_TENANT_PRE$proj_name
      tenant_id=$(awk -F'|' '/ id/{print $3}' $KS_TENANT_PRE$proj_name)
      echo -e "${YELLOW_COL}Project added ID: $tenant_id ${NORMAL_COL}"
      $COMMAND keys_addrole admin $proj_name admin
    fi

    # For all OpenStack releases after 2023-05-10, it is required that Nova be configured to send service token
    openstack role show service | grep -iq service
    [ $? = 0 ] || openstack role create service
  fi
}

keystone_add_user(){
  if [ $# -ne 4 ];then
    echo "$SCRIPT keys_adduser user password project"
  else
    user_name=$2
    user_pass=$3
    proj_name=$4
    openstack user list | grep -wq "$user_name"
    [ $? = 0 ] || openstack user create --domain default --project $proj_name --password $user_pass $user_name > $KS_USER_PRE$user_name
    user_id=$(awk -F'|' '/ id/{print $3}' $KS_USER_PRE$user_name)
    echo -e "${YELLOW_COL}User ID: $user_id ${NORMAL_COL}"
  fi
}

keystone_add_role(){
  if [ $# -lt 3 ];then
    echo "$SCRIPT keys_addrole user project role"
  else
    user_name=$2
    proj_name=$3
    role_name=$4
    [ -z $role_name ] && role_name="admin"
    # 使用admin角色将用户添加到服务项目中
    openstack role add --project $proj_name --user $user_name service # send service token
    openstack role add --project $proj_name --user $user_name $role_name > $KS_ROLE_PRE$user_name
  fi
}

keystone_list(){
  if [ $# -ne 2 ];then
    echo "$SCRIPT keys_list user|role|tenant|service|endpoint"
  else
    type=$2
    if [ $type = "all" ];then
      for i in user role endpoint service;do
	echo -e "${YELLOW_COL}********************   $i List   ********************${NORMAL_COL}"
	openstack $i list
	echo
      done
    else
      echo -e "${YELLOW_COL}********************   $type List   *********************${NORMAL_COL}"
      openstack "$type" list
    fi
  fi
}

keystone_add_service(){
  if [ $# -ne 4 ];then
    echo "$SCRIPT keys_addsrv service type desc"
  else
    service_name=$2
    type=$3
    desc=$4
    openstack service list|grep -wq $service_name
    [ $? = 0 ] || openstack service create --name $service_name --description "$desc" $type > $KS_SERV_PRE$service_name
    serv_id=$(awk -F'|' '/ id/{print $3}' $KS_SERV_PRE$service_name)
    echo -e "${YELLOW_COL}Service ID: $serv_id ${NORMAL_COL}"
  fi
}

keystone_add_endpoint(){
  if [ $# -ne 3 ];then
    echo "$SCRIPT keys_addept service url project"
  else
    service_name=$2
    url=$3
    proj_name=$4
    openstack endpoint list | grep -wq "$service_name"
    if [ $? != 0 ];then
      openstack endpoint create --region $REGION $service_name public $url
      openstack endpoint create --region $REGION $service_name internal $url
      openstack endpoint create --region $REGION $service_name admin $url
    fi
  fi
}

glance_init(){
  echo -e "${YELLOW_COL}Install Glance Images API v2${NORMAL_COL}"
  for srv in qemu-img openstack-glance;do
    dnf list installed | grep -iq $srv
    [ $? != 0 ] && dnf install -y $srv
  done

  mysql -uroot -p"$DBROOTPW" -e 'CREATE DATABASE IF NOT EXISTS glance;'
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  cat > /etc/glance/glance-api.conf <<EOF
[DEFAULT]
debug = $DEBUG
bind_host = $MY_IP
transport_url = rabbit://guest:$DBPASSWD@$CCVIP:5672/

[database]
connection = mysql+pymysql://glance:$DBPASSWD@$DBVIP:$MY_PORT/glance

[keystone_authtoken]
www_authenticate_uri = $KEYS_AUTH_URL
auth_url = $KEYS_ADMIN_URL
memcached_servers = $MEMCACHES
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = $ADMIN_PASS

[paste_deploy]
flavor = keystone

EOF

if [ $STORE_BACKEND = "ceph" ];then
  cat >> /etc/glance/glance-api.conf <<EOF
[glance_store]
stores = rbd
default_store = rbd
rbd_store_pool = images
rbd_store_user = glance        
show_image_direct_url = True
rbd_store_ceph_conf = /etc/ceph/ceph.conf
rbd_store_chunk_size = 8
EOF
else
  cat >> /etc/glance/glance-api.conf <<EOF
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
EOF
fi

if [ $(ls -al /var/lib/mysql/glance/* | wc -l) -lt 10 ];then
  su -s /bin/sh -c "glance-manage db sync" glance

  $COMMAND keys_adduser glance $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole glance $TENANT_NAME
  $COMMAND keys_addsrv  glance image 'OpenStack Image Service'
  $COMMAND keys_addept  image $IMAGE_URL
fi

  for svc in api ;do
    systemctl enable --now openstack-glance-$svc
  done
}

glance_add_image(){
  if [ $# -ne 3 ];then
    echo "$SCRIPT gls_add image_desc image_filename"
  else
    desc="$2"
    filename=$3
    FORMAT="--container-format bare --disk-format raw"

    file $filename | grep -q -i 'iso'
    [ $? = 0 ] && FORMAT="--container-format ovf --disk-format iso"
    
    file $filename | grep -q -i 'qcow'
    if [ $? = 0 ] ;then
      FORMAT="--container-format ovf --disk-format qcow2"
      if [ $STORE_BACKEND = "ceph" ];then
	echo -e "${YELLOW_COL}Convert image from qcow -> raw with ceph support ${NORMAL_COL}"
	qemu-img convert -f qcow2 -O raw $filename ${filename}.raw
	FORMAT="--container-format bare --disk-format raw"
	filename=${filename}.raw
      fi
    fi

    openstack image create "$desc" --public $FORMAT --file $filename \
	    --property hw_disk_bus=scsi \
	    --property hw_qemu_guest_agent=yes \
	    --property hw_scsi_model=virtio-scsi \
	    --property os_require_quiesce=yes
  fi
}

glance_list_image(){
  openstack image list -f table --fit-width
}

glance_show_image(){
  if [ $# -ne 2 ];then
    echo "$SCRIPT gls_show image_id"
  else
    openstack image show "$2" -f table --fit-width --human-readable
  fi
}

placement_init(){
if [ ${NODE_TYPE,,} != "compute" ];then
  echo -e "${YELLOW_COL}Install PLACEMENT Component ${NORMAL_COL}"
  dnf list installed | grep -iq openstack-placement-api
  [ $? != 0 ] && dnf install -y openstack-placement-api

  mysql -uroot -p"$DBROOTPW" -e 'CREATE DATABASE IF NOT EXISTS placement;'
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  cat > /etc/placement/placement.conf <<EOF
[placement_database]
connection = mysql+pymysql://placement:$DBPASSWD@$DBVIP:$MY_PORT/placement

[api]
auth_strategy = keystone

[keystone_authtoken]
auth_url = $KEYS_ADMIN_URL
memcached_servers = $MEMCACHES
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = placement
password = $ADMIN_PASS
EOF

if [ $(ls -al /var/lib/mysql/placement/* | wc -l) -lt 10 ];then
  su -s /bin/sh -c "placement-manage db sync" placement

  $COMMAND keys_adduser placement $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole placement $TENANT_NAME
  $COMMAND keys_addsrv  placement placement  'OpenStack Placement API'
  $COMMAND keys_addept  placement $PLACEMENT_URL
fi

  echo -e "${YELLOW_COL}placement need a patch!!! ${NORMAL_COL}"
  sed -r -i '/<Directory/, /Directory>/d' /etc/httpd/conf.d/00-placement-api.conf
  cat > .patch <<EOF
  <Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
  </Directory>
EOF
  sed -r -i '/ErrorLog /r .patch' /etc/httpd/conf.d/00-placement-api.conf
  sed -r -i "/Listen/s@.*@Listen $MY_IP:8778@g" /etc/httpd/conf.d/00-placement-api.conf
  systemctl restart httpd

  pip3 install osc-placement
  echo -e "${YELLOW_COL}pip3 install osc-placement ${NORMAL_COL}"
  echo -e "${YELLOW_COL}openstack --os-placement-api-version 1.6 trait list --sort-column name ${NORMAL_COL}"
fi
}

nova_init(){
  placement_init

  echo -e "${YELLOW_COL}Install *NOVA* Computer v2${NORMAL_COL}"
  for svc in api metadata-api conductor novncproxy scheduler compute;do
    svc="openstack-nova-$svc"
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc 
    [ $? != 0 ] && dnf install -y $svc
  done

if [ ${NODE_TYPE,,} != "compute" ];then
  for ndb in nova_api nova nova_cell0;do
    mysql -uroot -p"$DBROOTPW" -e "CREATE DATABASE IF NOT EXISTS $ndb;"
    mysql -uroot -p"$DBROOTPW" -e " \
    GRANT ALL PRIVILEGES ON $ndb.* TO 'nova'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
    GRANT ALL PRIVILEGES ON $ndb.* TO 'nova'@'%' IDENTIFIED BY '"$DBPASSWD"'; "
  done

  if [ $(ls -al /var/lib/mysql/nova/* | wc -l) -lt 10 ];then
    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
    su -s /bin/sh -c "nova-manage db sync" nova
  fi

  $COMMAND keys_adduser nova $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole nova $TENANT_NAME
  $COMMAND keys_addsrv  nova compute  'OpenStack Compute'
  $COMMAND keys_addept  compute $NOVA_URL
fi

# 如果有额外挂载的大硬盘，则把nova的实例目录迁移到新目录下
df -h|grep -wq /disk/nvme-disk
if [ $? = 0 ];then
  if [ ! -L /var/lib/nova ];then 
    if [ ! -d /disk/nvme-disk/nova ] ;then
      mv /var/lib/nova /disk/nvme-disk/
      ln -snf /disk/nvme-disk/nova /var/lib/
    fi
  fi
  chmod 1777 /disk/nvme-disk
fi

  cat > /etc/nova/nova.conf <<EOF
[DEFAULT]
debug = $DEBUG
my_ip = $MY_IP
region_name = $REGION
initial_cpu_allocation_ratio = $CPU_RATIO
initial_ram_allocation_ratio = $MEM_RATIO
initial_disk_allocation_ratio = 1.0
#reserved_host_memory_mb = 10240
metadata_host = \$my_ip
metadata_listen = \$my_ip
metadata_listen_port = 8775
osapi_compute_listen = \$my_ip
osapi_compute_listen_port = 8774

# 允许在同一台机器上扩容
allow_resize_to_same_host = true
state_path = /var/lib/nova

use_neutron = true
enabled_apis = osapi_compute,metadata
compute_driver = libvirt.LibvirtDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
transport_url = rabbit://guest:$DBPASSWD@$CCVIP:5672/

[api_database]
connection = mysql+pymysql://nova:$DBPASSWD@$DBVIP:$MY_PORT/nova_api

[database]
connection = mysql+pymysql://nova:$DBPASSWD@$DBVIP:$MY_PORT/nova

[api]
auth_strategy = keystone

[service_user]
send_service_user_token = True
project_name = service
user_domain_name = default
project_domain_name = default
auth_type = password
username = nova
password = $ADMIN_PASS
auth_url = $KEYS_ADMIN_URL

[keystone_authtoken]
service_token_roles_required = True
service_token_roles = service
project_name = service
user_domain_name = default
project_domain_name = default
auth_type = password
username = nova
password = $ADMIN_PASS
memcached_servers = $MEMCACHES
auth_url = $KEYS_ADMIN_URL
www_authenticate_uri = $KEYS_AUTH_URL

[vnc]
enabled = true
server_listen = \$my_ip
server_proxyclient_address = \$my_ip
novncproxy_host = \$my_ip
novncproxy_port = 6080
# internet loadbalance ip
novncproxy_base_url = http://\$my_ip:6081/vnc_auto.html

[glance]
api_servers = ${IMAGE_URL%v2}

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = $REGION
project_domain_name = default
project_name = service
auth_type = password
user_domain_name = default
auth_url = $KEYS_ADMIN_URL
username = placement
password = $ADMIN_PASS

[filter_scheduler]
enabled_filters = AggregateInstanceExtraSpecsFilter, AvailabilityZoneFilter, ComputeFilter, ComputeCapabilitiesFilter, ImagePropertiesFilter, ServerGroupAntiAffinityFilter, ServerGroupAffinityFilter, PciPassthroughFilter
available_filters = nova.scheduler.filters.all_filters

[libvirt]
virt_type = $VIRT_TYPE
cpu_mode = host-passthrough
EOF

  if [ $STORE_BACKEND = "ceph" ];then
  dnf install -y python3-rbd ceph-common
  cat >> /etc/nova/nova.conf <<EOF
#images_type = rbd
#images_rbd_pool = vms
#images_rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_user = cinder
rbd_secret_uuid = $MY_UUID
disk_cachemodes="network=writeback"
inject_password = false
inject_key = false
inject_partition = -2
live_migration_flag="VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_PERSIST_DEST,VIR_MIGRATE_TUNNELLED"
hw_disk_discard = unmap
EOF
  fi

  echo -e "${YELLOW_COL}nova-manage cell_v2 list_cells ${NORMAL_COL}"
  echo -e "${YELLOW_COL}nova-manage cell_v2 discover_hosts --verbose ${NORMAL_COL}"
  echo -e "${YELLOW_COL}nova-status upgrade check ${NORMAL_COL}"
  for obj in hypervisor catalog compute;do
    [ $obj = "compute" ] && obj="compute service"
    echo -e "${YELLOW_COL}openstack $obj list ${NORMAL_COL}"
  done

  [ ${NODE_TYPE,,} != "compute" ] && nova-status upgrade check
}

libvirt_check_start(){
  grep -wq listen /etc/sysconfig/libvirtd
  if [ $? = 0 ];then
    sed -r -i '/listen/s@#@@g' /etc/sysconfig/libvirtd
  else
    echo "LIBVIRTD_ARGS=\"--listen\"" >> /etc/sysconfig/libvirtd
  fi

  for svc in libvirtd libvirtd-ro libvirtd-admin libvirtd-tls libvirtd-tcp;do
    systemctl status $svc.socket | grep -qw masked
    [ $? = 0 ] || systemctl mask $svc.socket
  done

ss -ntpl|grep -qw libvirtd
if [ $? != 0 ];then
  cat > /etc/libvirt/libvirtd.conf <<EOF
listen_tls = 0
listen_tcp = 1
auth_tcp = "none"
auth_unix_ro = "none"
auth_unix_rw = "none"
unix_sock_group = "root"
unix_sock_rw_perms = "0777"
log_filters="1:qemu 1:libvirt 4:object 4:json 4:event 1:util"
log_outputs="3:syslog:libvirtd"
tcp_port = "16509"
listen_addr = "$MY_IP"
EOF
  systemctl daemon-reload
fi

  # very important!!!
  if [ ${NODE_TYPE,,} != "control" ];then
    for svc in libvirtd libvirt-guests ksm ksmtuned;do
      echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
      systemctl enable --now $svc
    done
  else
    for svc in libvirtd libvirt-guests ksm ksmtuned;do
      systemctl status $svc | grep -iq "active (running)"
      [ $? = 0 ] && systemctl disable --now $svc
    done
  fi
}

nova_all(){
# 如果是计算节点，需要启用以下服务
  libvirt_check_start

  for svc in api conductor novncproxy scheduler compute;do
    echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
    systemctl enable --now openstack-nova-$svc
  done
}

nova_control(){
  # very important!!!
  for svc in rabbitmq-server httpd mariadb memcached ;do
      systemctl status $svc | grep -iq "active (running)"
      if [ $? != 0 ];then
	echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
	systemctl enable --now $svc
      fi
  done
  
  for svc in api conductor novncproxy scheduler;do
    echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
    systemctl enable --now openstack-nova-$svc
  done

  for svc in metadata-api compute ;do
    systemctl status openstack-nova-$svc|grep -iq "active (running)"
    if [ $? = 0 ];then
      echo -e "${YELLOW_COL}-> Stopping Service $svc  ${NORMAL_COL}"
      systemctl disable --now openstack-nova-$svc
    fi
  done
}

nova_compute(){
  # very important!!!
  #sed -r -i '/enabled_apis/d' /etc/nova/nova.conf
  #openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis metadata,ec2,osapi_compute
  libvirt_check_start

  for svc in rabbitmq-server httpd nginx mariadb memcached ;do
    echo -e "${YELLOW_COL}-> Stopping Service $svc  ${NORMAL_COL}"
    systemctl disable --now $svc
  done

  for svc in api metadata-api conductor novncproxy scheduler;do
    echo -e "${YELLOW_COL}-> Stopping Service $svc  ${NORMAL_COL}"
    systemctl disable --now openstack-nova-$svc
  done

  for svc in compute ;do
    systemctl status openstack-nova-$svc|grep -iq "active (running)"
    if [ $? = 1 ];then
      echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
      systemctl enable --now openstack-nova-$svc
    fi
  done
}

nova_start(){
  if [ ${NODE_TYPE,,} = "all" ];then
    nova_all
  elif [ ${NODE_TYPE,,} = "control" ];then
    nova_control
  else
    nova_compute
  fi
}

nova_stop(){
  for svc in api metadata-api conductor novncproxy scheduler compute;do
    systemctl status openstack-nova-$svc|grep -iq "active (running)"
    if [ $? = 0 ];then
      echo -e "${YELLOW_COL}-> Stopping Service $svc  ${NORMAL_COL}"
      systemctl stop openstack-nova-$svc
    fi
  done
}

nova_restart(){
  nova_stop
  nova_start
}

nova_check(){
  #if [ ${NODE_TYPE,,} != "compute" ];then
  #  systemctl status libvirtd
  #  for svc in api conductor novncproxy scheduler compute;do
  #    echo -e "${GREEN_COL}-> Checking Service $svc ${NORMAL_COL}"
  #    systemctl status openstack-nova-$svc
  #  done
  #else
  #  systemctl status openstack-nova-compute
  #fi

  nova-manage cell_v2 discover_hosts --verbose
  openstack hypervisor list --sort-column "State" --sort-descending
  openstack compute service list --sort-column Binary -c Host -c Binary -c Zone -c Status -c State --fit-width
  openstack service list --fit-width
  echo
  openstack security group rule list --ingress --sort-column 'Security Group'
  echo -e "${GREEN_COL}"
  echo "+-------------------------- Bridge Info ------------------------+"
  brctl show
  echo "+--------------------------- IP Rules --------------------------+"
  ip ru
  echo "+--------------------------- IP Route --------------------------+"
  ip ro
  echo -en ${NORMAL_COL}
  #probe_hypervisor
}

nova_addrule(){
  openstack security group rule create --remote-ip 0.0.0.0/0 --protocol icmp default
  openstack security group rule create --remote-ip 0.0.0.0/0 --protocol tcp --dst-port 22 default
  openstack security group rule create --remote-ip 0.0.0.0/0 --protocol udp --dst-port 123 --egress default
}

neutron_init(){
  echo -e "${YELLOW_COL}Install *Neutron* Network ${NORMAL_COL}"
  #neutron-openvswitch openstack-neutron-ovn-metadata-agent ovn-2021-central ovn-2021-host
  for svc in neutron neutron-ml2 neutron-linuxbridge;do
    svc="openstack-$svc"
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc 
    [ $? != 0 ] && dnf install -y $svc
  done

if [ ${NODE_TYPE,,} = "control" ];then
  mysql -uroot -p"$DBROOTPW" -e "CREATE DATABASE IF NOT EXISTS neutron;"
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  if [ $(ls -al /var/lib/mysql/neutron/* | wc -l) -lt 10 ];then
  $COMMAND keys_adduser neutron $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole neutron $TENANT_NAME
  $COMMAND keys_addsrv  neutron network  'OpenStack Networking'
  $COMMAND keys_addept  network $NEUTRON_URL
  fi
fi

  cat > /etc/neutron/neutron.conf <<EOF
[DEFAULT]
debug = $DEBUG
bind_host = $MY_IP
transport_url = rabbit://guest:$DBPASSWD@$CCVIP:5672/
core_plugin = ml2
allow_overlapping_ips = true
auth_strategy = keystone

# Floating IP port forwarding
service_plugins = router,segments,port_forwarding
# DHCP HA
dhcp_agents_per_network = 2
# L3 HA
l3_ha = True
max_l3_agents_per_router = 2
min_l3_agents_per_router = 2

notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[database]
connection = mysql+pymysql://neutron:$DBPASSWD@$DBVIP:$MY_PORT/neutron

[keystone_authtoken]
www_authenticate_uri = $KEYS_AUTH_URL
auth_url = $KEYS_ADMIN_URL
memcached_servers = $MEMCACHES
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $ADMIN_PASS

[nova]
auth_url = $KEYS_ADMIN_URL
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = $REGION
project_name = service
username = nova
password = $ADMIN_PASS

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF

  sed -r -i '/ml2/,$d' /etc/neutron/plugins/ml2/ml2_conf.ini
  cat >> /etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
[ml2]
type_drivers = flat,vlan,vxlan

# vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 10000:20000

[securitygroup]
enable_ipset = true
EOF

  sed -r -i '/interface_driver/,$d' /etc/neutron/dhcp_agent.ini
  cat >> /etc/neutron/dhcp_agent.ini <<EOF
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
force_metadata = true
EOF

  cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini <<EOF
[linux_bridge]
physical_interface_mappings = provider:$PROVIDER_INTERFACE

[vxlan]
enable_vxlan = true
# 默认是租户网络，如果没有独立租户网络，就共用控制网络
local_ip = $MY_IP
l2_population = false

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF

  sed -r -i '/nova_metadata_host/, /metadata_proxy_shared_secret/d' /etc/neutron/metadata_agent.ini
  sed -r -i "/^\[DEFAULT\]/a nova_metadata_host = $CCVIP\nmetadata_proxy_shared_secret = $ADMIN_PASS"  /etc/neutron/metadata_agent.ini

  sed -r -i '/^debug/d; /interface_driver/d; /\[agent\]/, $d' /etc/neutron/l3_agent.ini
  sed -r -i "/^\[DEFAULT\]/a debug = $DEBUG\ninterface_driver = linuxbridge\n" /etc/neutron/l3_agent.ini
  cat >> /etc/neutron/l3_agent.ini <<EOF
[agent]
extensions = port_forwarding
EOF

  sed -r -i '/\[neutron\]/,/service_metadata_proxy/d' /etc/nova/nova.conf
  cat >> /etc/nova/nova.conf <<EOF

[neutron]
url = $NEUTRON_URL
auth_url = $KEYS_ADMIN_URL
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = $REGION
project_name = service
username = neutron
password = $ADMIN_PASS
metadata_proxy_shared_secret = $ADMIN_PASS
service_metadata_proxy = true
EOF

  ln -snf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

[ ${NODE_TYPE,,} = "control" ] && su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
  neutron_start
}

neutron_addnet(){
  echo "For example: "
  echo "openstack network create upnet --provider-network-type vxlan --share"
  echo "openstack subnet create devops --network upnet --subnet-range 192.168.0.0/24"
}

neutron_start(){
  if [ ${NODE_TYPE,,} = "control" ] || [ ${NODE_TYPE,,} = "all" ];then
    echo -e "${GREEN_COL}-> Restarting Service nova-api  ${NORMAL_COL}"
    systemctl restart openstack-nova-api
  fi

  #如果是网络选项2：自服务网络，同样也启用并启动layer-3服务：
  if [ ${NODE_TYPE,,} = "network" ] || [ ${NODE_TYPE,,} = "all" ];then
    for svc in server linuxbridge-agent dhcp-agent metadata-agent l3-agent;do
      echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
      systemctl enable --now neutron-$svc
    done
  fi

  if [ ${NODE_TYPE,,} = "compute" ] || [ ${NODE_TYPE,,} = "all" ];then
    echo -e "${GREEN_COL}-> Restarting Service nova-compute  ${NORMAL_COL}"
    systemctl restart openstack-nova-compute
  fi

  for svc in linuxbridge-agent ;do
    echo -e "${GREEN_COL}-> Restarting Service $svc  ${NORMAL_COL}"
    systemctl enable --now neutron-$svc
    systemctl restart neutron-$svc
  done
}

neutron_stop(){
  for svc in dhcp-agent l3-agent metadata-agent server;do
    systemctl status neutron-$svc|grep -iq "active (running)"
    if [ $? = 0 ];then
      echo -e "${YELLOW_COL}-> Stopping Service $svc  ${NORMAL_COL}"
      systemctl disable --now neutron-$svc
      systemctl stop neutron-$svc
    fi
  done
}

neutron_restart(){
  neutron_stop
  neutron_start
}

neutron_check(){
  #if [ ${NODE_TYPE,,} != "compute" ];then
  #  for svc in server linuxbridge-agent dhcp-agent metadata-agent l3-agent;do
  #    echo -e "${GREEN_COL}-> Checking Service $svc  ${NORMAL_COL}"
  #    systemctl status neutron-$svc
  #  done
  #else
  #  for svc in linuxbridge-agent ;do
  #    echo -e "${GREEN_COL}-> Checking Service $svc  ${NORMAL_COL}"
  #    systemctl status neutron-$svc
  #  done
  #fi
  echo -e "${YELLOW_COL}openstack network agent list  ${NORMAL_COL}"
  openstack network agent list --sort-column "Agent Type" -c "Agent Type" -c Host -c Alive -c State -c Binary --fit-width
  openstack network list --fit-width
  openstack floating ip list --fit-width
}

cinder_init(){
## openstack volume type create --public --property volume_backend_name="ceph" ceph_rbd
## openstack volume type create --public --property volume_backend_name="lvm" local_lvm
## openstack volume create --type ceph_rbd --size 1 ceph_rbd_vol01

  s_host=$(hostname -s)

  echo -e "${YELLOW_COL}Install Cinder Volume v3 ${NORMAL_COL}"
  if [ $STORE_BACKEND = "lvm" ];then
    if [ -x /usr/sbin/pvdisplay ];then
      pvdisplay | grep -iq cinder-volumes
      [ $? != 0 ] && echo -e "${RED_COL}cinder-volumes Not Created!${NORMAL_COL}" && sleep 3
    else
      echo -e "${RED_COL}LVM2 Not Installed!${NORMAL_COL}"
      exit 0
    fi
  #else
    #ceph health | grep -qw HEALTH_OK
    #[ $? = 1 ] && echo -e "${RED_COL}Ceph Have Problem!${NORMAL_COL}" && exit 0
  fi

  for svc in openstack-cinder lvm2 device-mapper-persistent-data targetcli python3-keystone python3-rbd ;do
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc
    [ $? != 0 ] && dnf install -y $svc
  done

  mysql -uroot -p"$DBROOTPW" -e 'CREATE DATABASE IF NOT EXISTS cinder;'
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  cat > /etc/cinder/cinder.conf <<EOF
[database]
connection = mysql+pymysql://cinder:$DBPASSWD@$DBVIP:$MY_PORT/cinder

[DEFAULT]
debug = $DEBUG
osapi_volume_listen = $MY_IP
my_ip = $MY_IP
transport_url = rabbit://guest:$DBPASSWD@$CCVIP:5672/
auth_strategy = keystone
glance_api_version = 2
glance_api_servers = $IMAGE_URL
enabled_backends = ceph,lvm
quota_volumes = 100
quota_snapshots = 100
quota_gigabytes=100000

[keystone_authtoken]
www_authenticate_uri = $KEYS_AUTH_URL
auth_url = $KEYS_ADMIN_URL
memcached_servers = $MEMCACHES
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = $ADMIN_PASS

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = nvme-disk
volume_backend_name = lvm-$s_host
target_helper = lioadm

[ceph]
volume_driver = cinder.volume.drivers.rbd.RBDDriver
rbd_pool = volumes
rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_flatten_volume_from_snapshot = false
rbd_max_clone_depth = 5
rbd_store_chunk_size = 4
rados_connect_timeout = -1
rbd_user = cinder
rbd_secret_uuid = $MY_UUID
volume_backend_name = ceph-$s_host

## 同一机房内意义不大
#backup_driver = cinder.backup.drivers.ceph
#backup_ceph_conf = /etc/ceph/ceph.conf
#backup_ceph_user = cinder-backup
#backup_ceph_chunk_size = 134217728
#backup_ceph_pool = backups
#backup_ceph_stripe_unit = 0
#backup_ceph_stripe_count = 0
#restore_discard_excess_bytes = true
EOF

if [ $(ls -al /var/lib/mysql/cinder/* | wc -l) -lt 10 ];then
  $COMMAND keys_adduser cinder $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole cinder $TENANT_NAME
  #$COMMAND keys_addsrv  cinderv2 volumev2  'OpenStack Block Service v2'
  #$COMMAND keys_addept  volumev2 $VOLUME_URL/v2
  $COMMAND keys_addsrv  cinderv3 volumev3  'OpenStack Block Service v3'
  $COMMAND keys_addept  volumev3 $VOLUME_URL

  su -s /bin/sh -c "cinder-manage db sync" cinder
fi

  for svc in api scheduler volume;do
    systemctl enable --now openstack-cinder-$svc
  done

  for svc in target iscsid;do
    systemctl enable --now $svc
  done
  echo -e "${YELLOW_COL}openstack volume service list  ${NORMAL_COL}"
}

cinder_start(){
  for svc in api scheduler volume;do
    systemctl enable --now openstack-cinder-$svc
  done
}

cinder_stop(){
  for svc in api scheduler volume;do
    systemctl disable --now openstack-cinder-$svc
  done
}

cinder_restart(){
	cinder_stop
	cinder_start
}

cinder_check(){
  openstack volume service list
  openstack volume list
  openstack volume type list
  openstack volume qos list
}

probe_ceph(){
## virsh dumpxml instance-0000025e | grep protocol
  cat > /root/ceph-auth.sh <<EOF
ceph auth get-or-create client.cinder mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=volumes, allow rwx pool=vms, allow rx pool=images'
ceph auth get-or-create client.glance mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=images'
ceph auth get-or-create client.cinder-backup mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=backups'

ceph auth get-or-create client.cinder > /etc/ceph/ceph.client.cinder.keyring
ceph auth get-or-create client.cinder-backup > /etc/ceph/ceph.client.cinder-backup.keyring
ceph auth get-or-create client.glance > /etc/ceph/ceph.client.glance.keyring

chown cinder.cinder /etc/ceph/*cinder*
chown glance.glance /etc/ceph/*glance*
EOF
sh /root/ceph-auth.sh

cat > /root/ceph_secret_virsh.xml <<EOF
<secret ephemeral='no' private='no'>
  <uuid>$MY_UUID</uuid>
  <usage type='ceph'>
    <name>client.cinder secret</name>
  </usage>
</secret>
EOF

  for node in $(openstack hypervisor list -c "Hypervisor Hostname" -f value);do
    scp /etc/ceph/ceph.client.[gc]* $node:/etc/ceph/
    scp /root/ceph_secret_virsh.xml $node:/root/
    echo -en "${YELLOW_COL} ------------- Virsh Patch $node -------------${NORMAL_COL}\n"
    ssh $node "virsh secret-define --file /root/ceph_secret_virsh.xml; virsh secret-set-value --secret $MY_UUID --base64 \$(awk '/key/{print \$NF}' /etc/ceph/ceph.client.cinder.keyring) ; virsh secret-list"
  done
}

probe_gpu(){
# ls -adl /sys/kernel/iommu_groups/*
# lspci -s 01:00.0 -k 
  GPU_NAME=$(lspci -nn| sed -r -n '/VGA.*NVIDIA/s@.*\[(.*)\].*\[.*@\1@gp'|tr ' ' '_'|sort -u)
  echo $GPU_NAME | grep -iq ^[a-zA-Z]
  [ $? = 1 ] && GPU_NAME=$GPUNAME
  sed -r -i '/\[pci\]/, /alias/d' /etc/nova/nova.conf

  dnf list --installed | grep -iq driverctl
  [ $? = 1  ] && dnf install -y driverctl
  lspci -nn | sed -r -n "/VGA.*NVIDIA/s@(.*) VGA.*\[(.*)\].*\[(.*):(.*)\].*@\1 \3 \4 #$GPU_NAME@gp" > .vendor_pcis

  echo -en "\n${YELLOW_COL}==========  Node: [ $(awk 'END{print NR}' .vendor_pcis) ] GPU Cards ==========\n${NORMAL_COL}"
  for id in $(lspci -nn |awk '/NVIDIA/{split($1,a,".");print a[1]}'|sort -u);do
    echo -en "\n${YELLOW_COL}==========  $id driver ==========\n${NORMAL_COL}"
      lspci -nnv -s $id | grep -iE "$id|Kernel driver"
      echo
  done

  awk '{print "\"address\":\""$1"\", \"vendor_id\":\""$2"\", \"product_id\":\""$3"\""}' .vendor_pcis > .vgacards
  awk '{print "\"address\":\""$1"\""}' .vendor_pcis > .vgacards
  while read item;do
    nova_str+="{$item}, "
  done < .vgacards
  nova_str=${nova_str%, }

  echo -en "\n${YELLOW_COL}---------->  compute node: >> nova.conf ${NORMAL_COL}
[pci]
passthrough_whitelist = [ ${nova_str} ]
"

  while read item;do
    GPU_NAME=$(echo $item | awk -F# '{gsub(" ","_",$2);print $2}' )
    alias_str+="alias = {\"name\": \"${GPU_NAME,,}\","
    alias_str+=$(echo $item | awk -F'#' '{print $1}'|awk '{print "\"vendor_id\":\""$2"\", \"product_id\":\""$3"\""}')
    alias_str+=", \"device_type\":\"type-PCI\"}\n"
    echo -en $alias_str >> .tmp.pcis
  done < .vendor_pcis

  sort -u .tmp.pcis -o .tmp.pcis
  echo -en "\n${YELLOW_COL}---------->  control node: >> nova.conf ${NORMAL_COL}
[pci]
$(cat .tmp.pcis)
"

cat >> /etc/nova/nova.conf<<EOF

[pci]
passthrough_whitelist = [ ${nova_str} ]
$(cat .tmp.pcis)
EOF

rm -rf .vendor_pcis .vgacards .tmp.pcis
##########################################
echo -en "\n${YELLOW_COL}--------------------------------------- \n${NORMAL_COL}"
echo -en "${YELLOW_COL}openstack flavor set m1.GPU --property \"pci_passthrough:alias\"=\"${GPU_NAME,,}:1\"\n${NORMAL_COL}"
echo -en "${YELLOW_COL}openstack flavor create c2m4d10g1 --vcpus 2 --ram 4096 --disk 10 --property \"pci_passthrough:alias\"=\"${GPU_NAME,,}:1\"\n${NORMAL_COL}"
#openstack flavor create c2m4d10g1  --vcpus 2 --ram 4096 --disk 10 --property "pci_passthrough:alias"="a1:1"
}

probe_hypervisor(){
  cat > .local_hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

  openstack compute service list -c "Host" -c "State" -f value|awk '/up/{print $1}'|sort -u > .all_hosts
  dig $(cat .all_hosts | tr '\n' ' ')|awk '/ANSWER SECTION/{getline;print $NF"\t"$1}' >> .local_hosts
  while read host;do
    rsync -az -e "ssh " .local_hosts $host:/etc/hosts
  done < .all_hosts

  openstack hypervisor list -c "Hypervisor Hostname" -f value | sort -u > .compute_hosts
  diff .all_hosts .compute_hosts |awk '{if($2!="") print $2}' > .control_hosts
  while read host;do
    rsync -az -e "ssh " /etc/keystone/fernet-keys/ $host:/etc/keystone/fernet-keys/
    rsync -az -e "ssh " /etc/keystone/credential-keys/ $host:/etc/keystone/credential-keys/
  done < .control_hosts
  rm -rf .*_hosts
}


octavia_init(){
  echo -e "${YELLOW_COL}Install *Octavia* LoadBalance ${NORMAL_COL}"
  for svc in octavia-api octavia-health-manager octavia-housekeeping octavia-worker ;do
    svc="openstack-$svc"
    echo -e "${YELLOW_COL}-> Installing $svc ... ${NORMAL_COL}"
    dnf list installed | grep -iq $svc 
    [ $? != 0 ] && dnf install -y $svc
  done

if [ ${NODE_TYPE,,} = "control" ];then
  mysql -uroot -p"$DBROOTPW" -e "CREATE DATABASE IF NOT EXISTS octavia;"
  mysql -uroot -p"$DBROOTPW" -e " \
  GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'localhost' IDENTIFIED BY '"$DBPASSWD"'; \
  GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'%' IDENTIFIED BY '"$DBPASSWD"'; "

  if [ $(ls -al /var/lib/mysql/octavia/* | wc -l) -lt 10 ];then
  $COMMAND keys_adduser octavia $ADMIN_PASS $TENANT_NAME
  $COMMAND keys_addrole octavia $TENANT_NAME
  $COMMAND keys_addsrv  octavia load-balancer 'OpenStack LBaaS'
  $COMMAND keys_addept  octavia $OCTAVIA_URL
  su -s /bin/sh -c "octavia-db-manage db sync" octavia
  fi
fi

  cat > /etc/octavia/octavia.conf <<EOF
[DEFAULT]
debug = $DEBUG
bind_host = $MY_IP
transport_url = rabbit://guest:$DBPASSWD@$CCVIP:5672/
auth_strategy = keystone

[database]
connection = mysql+pymysql://octavia:$DBPASSWD@$DBVIP:$MY_PORT/octavia

[health_manager]
bind_ip = $MY_IP
bind_port = 5555

[keystone_authtoken]
www_authenticate_uri = $KEYS_AUTH_URL
auth_url = $KEYS_ADMIN_URL
memcached_servers = $MEMCACHES
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = octavia
password = $ADMIN_PASS

[oslo_messaging]
topic = octavia_prov

# specify certificates created on [2]
[certificates]
ca_private_key = /etc/octavia/certs/private/server_ca.key.pem
ca_certificate = /etc/octavia/certs/server_ca.cert.pem
server_certs_key_passphrase = insecure-key-do-not-use-this-key
ca_private_key_passphrase = not-secure-passphrase

# specify certificates created on [2]
[haproxy_amphora]
server_ca = /etc/octavia/certs/server_ca-chain.cert.pem
client_cert = /etc/octavia/certs/private/client.cert-and-key.pem

# specify certificates created on [2]
[controller_worker]
client_ca = /etc/octavia/certs/client_ca.cert.pem
EOF
}

octavia_start(){
  if [ ${NODE_TYPE,,} = "control" ];then
    echo -e "${GREEN_COL}-> Restarting Service octavia api  ${NORMAL_COL}"
    systemctl restart octavia-api
  fi

  if [ ${NODE_TYPE,,} = "network" ];then
    for svc in health-manager housekeeping worker;do
      echo -e "${GREEN_COL}-> Starting Service $svc  ${NORMAL_COL}"
      systemctl enable --now octavia-$svc
    done
  fi
}

octavia_stop(){
  for svc in api health-manager housekeeping worker;do
    systemctl disable --now octavia-$svc
  done
}

octavia_restart(){
  octavia_stop
  octavia_start
}

case $1 in
  adjust_sys)
  	adjust_sys;;
  control_init)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	control_init;;
  env_clean)
  	env_clean;;
  keys_init)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_init;;
  keys_addproj)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_add_proj "$@";;
  keys_adduser)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_add_user "$@";;
  keys_addrole)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_add_role "$@";;
  keys_addsrv)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_add_service "$@";;
  keys_addept)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_add_endpoint "$@";;
  keys_list)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_list "$@";;
  keys_bind)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	keystone_user_role "$@";;
  gls_init)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	glance_init;;
  gls_add)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	glance_add_image "$@";;
  gls_show)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	glance_show_image "$@";;
  gls_check)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	glance_list_image;;
  gls_restart)
	systemctl daemon-reload ; systemctl restart openstack-glance-api ;;
  nova_init)
  	nova_init;;
  nova_start)
  	nova_start;;
  nova_stop)
  	nova_stop;;
  nova_restart)
  	nova_restart;;
  nova_check)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	nova_check;;
  nova_addrule)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	nova_addrule;;
  nova_control)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	nova_control;;
  nova_compute)
  	nova_compute;;
  nova_all)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	nova_all;;
  cinder_init)
  	cinder_init;;
  cinder_stop)
  	cinder_stop;;
  cinder_start)
  	cinder_start;;
  cinder_restart)
  	cinder_restart;;
  cinder_check)
  	cinder_check;;
  neutron_init)
  	neutron_init;;
  neutron_addnet)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	neutron_addnet;;
  neutron_start)
  	neutron_start;;
  neutron_stop)
  	neutron_stop;;
  neutron_restart)
  	neutron_restart;;
  neutron_check)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	neutron_check;;
  placement_init)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
  	placement_init;;
  probe_ceph)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
	probe_ceph;;
  probe_gpu)
	probe_gpu;;
  probe_hypervisor)
	[ $NODE_TYPE = "compute" ] && echo "Node is Compute!" && exit
	probe_hypervisor;;
  checkall)
	if [ $NODE_TYPE = "control" ];then 
	  SRV="httpd:80 mysql:3306 rabbitmq:4369 memcache:11211 nova:8774 cinder:8776 glance:9292 keystone:5000"
	elif [ $NODE_TYPE = "network" ];then 
	  SRV="neutron:9696"
	fi
	SRV="$SRV nova-compute neutron-linuxbridge-agent"
	for srv in $SRV;do
	  ss=`echo $srv|awk -F: '{print $1}'`
	  port=`echo $srv|awk -F: '{print $2}'`
	  if [ -z $port ];then
	    ps auxf|grep -iq $ss
	  else
	    ss -tnplu|grep -q ":$port "
	  fi
	  if [ $? = 0 ];then
  	    printf "%-28s is " $ss 
  	    echo -en "${GREEN_COL}"
  	    printf "%-10s \n" "OK!"
	  else
  	    printf "%-28s is " $ss 
  	    echo -en "${RED_COL}"
  	    printf "%-10s \n" "XXX"
	  fi
  	  echo -en ${NORMAL_COL}
	done;;
  *)
	check_env
  	echo -e "${RED_COL}$SCRIPT ${YELLOW_COL}adjust_sys|control_init|probe_ceph|probe_gpu|probe_hypervisor|checkall|env_clean"
  	echo -e "${RED_COL}$SCRIPT ${GREEN_COL}keys_init|keys_addproj|keys_adduser|keys_addrole|keys_addsrv|keys_addept|keys_bind|keys_list"
  	echo -e "${RED_COL}$SCRIPT ${GREEN_COL}gls_init|gls_add|gls_show|gls_check|gls_restart"
  	echo -e "${RED_COL}$SCRIPT ${GREEN_COL}cinder_init|cinder_stop|cinder_start|cinder_restart|cinder_check"
  	echo -e "${RED_COL}$SCRIPT ${YELLOW_COL}nova_init|nova_start|nova_stop|nova_restart|nova_addrule|nova_check"
  	echo -e "${RED_COL}$SCRIPT ${YELLOW_COL}neutron_init|neutron_addnet|neutron_start|neutron_stop|neutron_restart|neutron_check"
  	echo -e "${RED_COL}$SCRIPT ${YELLOW_COL}octavia_init|octavia_addnet|octavia_start|octavia_stop|octavia_restart|octavia_check"
  	echo -en ${NORMAL_COL}
esac
