#!/usr/bin/env bash
# Prints role (source/replica) and replication lag for both mysql pods.
set -euo pipefail

echo "== mysql-a-0 =="
echo "-- SHOW MASTER STATUS (populated if this server has replicas following it) --"
kubectl exec mysql-a-0 -- mysql -uroot -prootpass-a -e "SHOW MASTER STATUS\G" 2>&1 | grep -v Warning
echo "-- SHOW REPLICA STATUS (empty here = mysql-a is not a replica of anything = it's the source) --"
kubectl exec mysql-a-0 -- mysql -uroot -prootpass-a -e "SHOW REPLICA STATUS\G" 2>&1 | grep -v Warning

echo
echo "== mysql-b-0 =="
echo "-- SHOW REPLICA STATUS (role + lag) --"
kubectl exec mysql-b-0 -- mysql -uroot -prootpass-b -e "SHOW REPLICA STATUS\G" 2>&1 | grep -v Warning | \
  grep -E "Source_Host|Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source|Last_Error"
