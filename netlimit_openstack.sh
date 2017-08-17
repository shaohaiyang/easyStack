#nova-manage network list
#nova-manage network delete  183.134.101.128/27
#nova network-create upnet --bridge=br100 --multi-host=T --fixed-range-v4=158.118.218.1/24 --dns1=8.8.8.8 --gateway=158.118.218.1
#nova-manage floating create --ip_range=183.134.101.144/29  --pool CTC-ZJ-LNA

#tenantID=`keystone tenant-list|awk '/VPN-HKG-2/{print $2}'`
#echo $tenantID
#nova-manage network create upnet2 --bridge=br100 --fixed_range_v4=158.118.218.0/24 --dns1=8.8.8.8 --gateway=158.118.218.65 --project_id="$tenantID"

#nova boot --image centos6_bbr --flavor c1m1d10n10 --key_name _upyun --nic net-id=f57c4025-2226-49b9-ac55-15c922ba2e26 test-vm1
#exit

flavor="c1m1d10n5"
band="5" #mbps

burst=$((band*5))
band=$((band*135))
echo $band $burst

nova flavor-key $flavor set quota:vif_inbound_average=$band
nova flavor-key $flavor set quota:vif_inbound_peak=$((band+burst*2))
nova flavor-key $flavor set quota:vif_inbound_burst=$burst

nova flavor-key $flavor set quota:vif_outbound_average=$band
nova flavor-key $flavor set quota:vif_outbound_peak=$((band+burst*2))
nova flavor-key $flavor set quota:vif_outbound_burst=$burst
