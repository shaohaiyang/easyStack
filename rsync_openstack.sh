#!/bin/sh
SSH="ssh -i /root/.ssh/hzup.ssh -p65422 -o StrictHostKeyChecking=no "
SERVER="192.168.13.236#OPK-ZJ-FUD-C236"

cat > /var/lib/nova/.ssh/config <<EOF
StrictHostKeyChecking no
User nova
Port 65422
Identityfile ~/.ssh/id_rsa
EOF

STRING=
for SRV in $SERVER;do
        echo "$SRV"|grep -q "^#"
        [ $? = 0 ] && continue

	ip=`echo $SRV|cut -d# -f1`
	hostname=`echo $SRV|cut -d# -f2`

	STRING+="$ip\t$hostname\n"
	sed -r -i "/$ip/d;\$a $ip $hostname" /etc/hosts
done

for SRV in $SERVER;do
        echo "$SRV"|grep -q "^#"
        [ $? = 0 ] && continue

	ip=`echo $SRV|cut -d# -f1`
	hostname=`echo $SRV|cut -d# -f2`

	rsync -avz -e "$SSH" /root/easyStack_icehouse.sh $ip:/root/
	rsync -avz -e "$SSH" /etc/hosts $ip:/etc/
	rsync -avz -e "$SSH" /etc/nova/ $ip:/etc/nova/
	rsync -avz -e "$SSH" /var/lib/nova/.ssh/ $ip:/var/lib/nova/.ssh/
	rsync -avz -e "$SSH" /etc/dnsmasq.conf $ip:/etc/
	rsync -avz -e "$SSH" /etc/tgt/ $ip:/etc/tgt/
	rsync -avz -e "$SSH" /var/lib/keystone/ $ip:/var/lib/keystone/
	$SSH $ip -n "usermod -s /bin/bash nova"
	$SSH $ip -n "chkconfig ksm on;chkconfig ksmtuned on;chkconfig iptables off;chkconfig ip6tables off;chkconfig ntpd off"
	$SSH $ip -n "sed -r -i '/ip_forward/d' /etc/rc.d/rc.local;echo 'echo 1 > /proc/sys/net/ipv4/ip_forward' >> /etc/rc.d/rc.local"
	$SSH $ip -n "sed -r -i '/my_ip/s@=.*@= $ip@g;/vncserver_proxyclient_address/s@=.*@= $ip@g' /etc/nova/nova.conf"
	$SSH $ip -n "echo '* */3 * * * root (ntpdate -o3 0.pool.ntp.org 211.115.194.21 133.100.11.8 142.3.100.15)' > /etc/cron.d/ops_ntp"
	$SSH $ip -n "echo 1 > /proc/sys/net/ipv4/ip_forward"
	#$SSH $ip -n "openstack-config --set /etc/nova/nova.conf DEFAULT enabled_apis metadata,ec2,osapi_compute"
	#$SSH $ip -n "mkdir -p /disk/ssd1/nova-instances;chown -R nova.nova /disk/ssd1/nova-instances;ln -snf /disk/ssd1/nova-instances /var/lib/nova/instances"
	#$SSH $ip -n "/root/easyStack_icehouse.sh nova_to_compute"
    $SSH $ip -n "/etc/init.d/ntpd stop;ntpdate -o3 0.pool.ntp.org 211.115.194.21 133.100.11.8 142.3.100.15"
done
