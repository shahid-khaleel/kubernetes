# MySQL StatefulSet Replication on Minikube

Two independent MySQL 8.0 instances deployed as Kubernetes StatefulSets, wired
together with source → replica (master/slave) replication for hands-on
practice.

## Architecture

```
                    Headless Service              Headless Service
                    mysql-a (ClusterIP: None)     mysql-b (ClusterIP: None)
                            │                              │
                            ▼                              ▼
                    ┌───────────────┐              ┌───────────────┐
                    │   mysql-a-0   │  replication  │   mysql-b-0   │
                    │  server-id=1  │ ────────────► │  server-id=2  │
                    │   SOURCE      │  (GTID-based)  │   REPLICA     │
                    └───────┬───────┘                └───────┬───────┘
                            │                                │
                            ▼                                ▼
                    PVC data-mysql-a-0                PVC data-mysql-b-0
                       (1Gi, RWO)                        (1Gi, RWO)
```

- `mysql-a` is the **source** (master): all writes happen here.
- `mysql-b` is the **replica** (slave): it streams and applies `mysql-a`'s
  binary log via GTID auto-positioning.
- Each StatefulSet has its own headless Service, Secret, and PVC — they are
  fully independent Kubernetes objects; replication is configured
  imperatively on top (MySQL has no CRD/controller-native replication here).
- Per-pod DNS (`mysql-a-0.mysql-a`, `mysql-b-0.mysql-b`) is what lets the
  replica find the source reliably even after a reschedule.

## Prerequisites

- Minikube running (`minikube start --driver=docker`)
- `kubectl` pointed at the Minikube cluster
- Default `standard` StorageClass available (`kubectl get storageclass`)

## Deploy

```bash
kubectl apply -f manifests/
```

Wait for both pods to become `1/1 Ready`:

```bash
kubectl get pods -l 'app in (mysql-a,mysql-b)' -w
```

## Configure replication

Run once, after both pods are Ready:

```bash
bash scripts/setup-replication.sh
```

This:
1. Creates a `repl` user on `mysql-a` with the `REPLICATION SLAVE` privilege.
2. Runs `CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION=1` and
   `START REPLICA` on `mysql-b`, pointing it at `mysql-a-0.mysql-a:3306`.

## Verify

```bash
bash scripts/check-status.sh
```

Or manually:

```bash
# Interactive shell into either pod
kubectl exec -it mysql-a-0 -- mysql -uroot -prootpass-a
kubectl exec -it mysql-b-0 -- mysql -uroot -prootpass-b
```

Test replication end-to-end:

```bash
kubectl exec mysql-a-0 -- mysql -uroot -prootpass-a -e \
  "CREATE DATABASE IF NOT EXISTS demo; \
   CREATE TABLE IF NOT EXISTS demo.events (id INT AUTO_INCREMENT PRIMARY KEY, msg VARCHAR(100)); \
   INSERT INTO demo.events (msg) VALUES ('hello from source');"

kubectl exec mysql-b-0 -- mysql -uroot -prootpass-b -e "SELECT * FROM demo.events;"
```

## Identifying source vs. replica

Ask each server directly with `SHOW REPLICA STATUS\G` (MySQL 8.0.22+; older
versions use `SHOW SLAVE STATUS\G`):

| Result | Meaning |
|---|---|
| Empty set | This server is **not** a replica of anything → it's the source/master |
| Populated row, with `Source_Host` set | This server **is** a replica → `Source_Host`/`Source_Server_Id` name its master |

An empty set on the *source* is expected and correct — it's the proof that
nothing is upstream of it. An empty set on what you *expect* to be the
replica means replication was never started (`START REPLICA` wasn't run, or
failed).

## Checking replication lag

Only meaningful on the **replica** (`mysql-b`), via `SHOW REPLICA STATUS\G`:

| Field | Meaning |
|---|---|
| `Seconds_Behind_Source` | Seconds the replica is behind the source. `0` = caught up. `NULL` = replication is stopped/broken — check the two `Running` fields below, don't read NULL as "no lag" |
| `Replica_IO_Running` / `Replica_SQL_Running` | Both must be `Yes`. IO thread pulls binlog events from the source; SQL thread applies them locally |
| `Last_Error` / `Last_SQL_Error` | Non-empty means replication has broken (duplicate key, schema drift, etc.) and lag will grow unbounded until fixed |

`Seconds_Behind_Source` is a heuristic (timestamp delta on the last applied
event), not an exact queue depth — production setups often use a heartbeat
table (e.g., `pt-heartbeat`) for more precise lag measurement.

## PodDisruptionBudgets

Both StatefulSets run `replicas: 1`, so their PDBs
(`manifests/07-mysql-a-pdb.yaml`, `manifests/08-mysql-b-pdb.yaml`) use
`minAvailable: 1`. This is a deliberate edge case: with only one pod and a
floor of one, **no voluntary eviction is ever allowed** — `kubectl get pdb`
shows `ALLOWED DISRUPTIONS: 0` permanently. A `kubectl drain` of the node, or
the cluster autoscaler trying to reclaim it, will hang/retry forever against
this pod. This is a real production failure mode: a PDB budget that can never
be satisfied blocks node maintenance entirely.

Proof (bypasses node draining entirely — talks straight to the Eviction API
so nothing else on the cluster is touched):

```bash
kubectl proxy --port=8001 &
curl -X POST http://localhost:8001/api/v1/namespaces/default/pods/mysql-a-0/eviction \
  -H "Content-Type: application/json" \
  -d '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"mysql-a-0","namespace":"default"}}'
# -> 429 TooManyRequests: "needs 1 healthy pods and has 1 currently"
```

To make eviction possible again, either scale the StatefulSet up first (so
losing one pod still leaves `minAvailable` satisfied) or relax/delete the PDB
before maintenance — never leave a single-replica statefulful workload
guarded by `minAvailable` equal to its total replica count in production.

## Cleanup

```bash
kubectl delete -f manifests/
kubectl delete pvc data-mysql-a-0 data-mysql-b-0   # StatefulSets don't delete PVCs automatically
```

## Files

```
manifests/
  01-mysql-a-secret.yaml        Root password for mysql-a
  02-mysql-a-service.yaml       Headless Service (enables mysql-a-0.mysql-a DNS)
  03-mysql-a-statefulset.yaml   Source: server-id=1, GTID mode on
  04-mysql-b-secret.yaml        Root password for mysql-b
  05-mysql-b-service.yaml       Headless Service (enables mysql-b-0.mysql-b DNS)
  06-mysql-b-statefulset.yaml   Replica: server-id=2, GTID mode on
  07-mysql-a-pdb.yaml           PDB for mysql-a (minAvailable: 1)
  08-mysql-b-pdb.yaml           PDB for mysql-b (minAvailable: 1)
scripts/
  setup-replication.sh          One-time replication bootstrap
  check-status.sh                Prints role + lag for both pods
```

## Notes

- Credentials here (`rootpass-a`, `rootpass-b`, `replpass`) are plaintext in
  Secrets for local learning only — not suitable beyond Minikube.
- Single replica each (`replicas: 1`); scaling either StatefulSet up does
  **not** automatically wire new pods into replication — that's manual, same
  as the initial setup.
