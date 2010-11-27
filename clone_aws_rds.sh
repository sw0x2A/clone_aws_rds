#!/bin/bash
# I used this script to clone RDS instance on a daily basis for reporting 
# purposes. Since Amazon introduced read-only replicas for AWS RDS instances,
# this script became useless.

# load Amazon environment settings
source aws_config

TODAY=$(date --date '-0 days' +%Y%m%d)
YESTERDAY=$(date --date '-1 days' +%Y%m%d)

PRODDB="dbname"
REPORTINGDB="${PRODDB}-reporting"
SNAPSHOTID="${PRODDB}-${TODAY}"
OLDSNAPSHOTID="${PRODDB}-${YESTERDAY}"
DBCLASS="db.m1.small"

# Create new and remove old db snapshot
rds-create-db-snapshot ${PRODDB} --db-snapshot-identifier=${SNAPSHOTID} --quiet
rds-delete-db-snapshot ${OLDSNAPSHOTID} --force --quiet

# Delete yesterdays reporting instance
rds-delete-db-instance ${REPORTINGDB} --force --skip-final-snapshot --quiet

# Wait until old instance is deleted
IS_DELETED=$(rds-describe-db-instances | grep -c ${REPORTINGDB} )
while [ "${IS_DELETED}" != 0 ]
do
        sleep 5
        IS_DELETED=$(rds-describe-db-instances | grep -c ${REPORTINGDB} )
done

# Restore new instance from latest snapshot
rds-restore-db-instance-from-db-snapshot ${REPORTINGDB} \
	--db-snapshot-identifier=${SNAPSHOTID} \
	--db-instance-class=${DBCLASS} --quiet

# Wait until new instance is available
RDBHOST=$(rds-describe-db-instances ${REPORTINGDB} | awk '/available/{ print $9 }')
while [ "${RDBHOST:(-18)}" != ".rds.amazonaws.com" ]
do
	sleep 60
	RDBHOST=$(rds-describe-db-instances ${REPORTINGDB} | awk '/available/{ print $9 }')
done

# Grant privileges to BI users
# We have to wait here for a while because sometimes connection to new 
# RDS instance was not reliable in the first minutes
sleep 240
mysql 	-h ${RDBHOST} \
	-e "GRANT SELECT , SHOW VIEW ON * . * TO 'user1'@'%';" \
	-e "GRANT SELECT , SHOW VIEW ON * . * TO 'user2'@'%';" \
	-e "GRANT SELECT , SHOW VIEW ON * . * TO 'user3'@'%';"

