#!/bin/sh
find /root/sql_backup/ -mtime +7 -type f | xargs rm -rf

ROOTPW="FPkGgdStb4(Z"
mysqldump -uroot -p$ROOTPW --all-databases > /root/sql_backup/openstack.sql.`date +'%Y_%m_%d_%H'`

service openstack-nova-api reload
