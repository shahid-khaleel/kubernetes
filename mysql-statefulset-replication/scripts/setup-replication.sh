#!/usr/bin/env bash
# Configures mysql-a as the replication source and mysql-b as its replica.
# Run once, after both StatefulSet pods are Running and Ready.
set -euo pipefail

SOURCE_POD=mysql-a-0
REPLICA_POD=mysql-b-0
SOURCE_SVC=mysql-a
SOURCE_ROOT_PASS=rootpass-a
REPLICA_ROOT_PASS=rootpass-b
REPL_USER=repl
REPL_PASS=replpass

echo "Creating replication user on ${SOURCE_POD}..."
kubectl exec "${SOURCE_POD}" -- mysql -uroot -p"${SOURCE_ROOT_PASS}" -e "
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PASS}';
GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';
FLUSH PRIVILEGES;
"

echo "Pointing ${REPLICA_POD} at ${SOURCE_POD} (GTID auto-position)..."
kubectl exec "${REPLICA_POD}" -- mysql -uroot -p"${REPLICA_ROOT_PASS}" -e "
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${SOURCE_POD}.${SOURCE_SVC}',
  SOURCE_PORT=3306,
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PASS}',
  SOURCE_AUTO_POSITION=1;
START REPLICA;
"

echo "Done. Verify with scripts/check-status.sh"
