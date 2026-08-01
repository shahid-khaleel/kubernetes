# configmap-rotations

A Spring Boot demo whose `application.yaml` is supplied entirely by a
Kubernetes `ConfigMap` mounted as a volume, used to demonstrate ConfigMap
propagation, rollout mechanics, and the gotchas around "when does a running
pod actually see a config change".

The app exposes one endpoint:

```
GET /feature -> {"feature.enabled": false, "pod": "config-demo-7d4...", "servedAt": "..."}
```

`feature.enabled` is bound once at startup via `@Value("${feature.enabled}")`
in [FeatureController.java](src/main/java/com/example/configrotation/FeatureController.java)
— it will not change for an already-running pod, which is the crux of
everything below.

## Layout

```
pom.xml, src/                 Spring Boot app (Maven)
Dockerfile                    Multi-stage build -> config-demo:latest
k8s/namespace.yaml            Namespace: configmap-rotations
k8s/configmap.yaml            ConfigMap holding application.yaml (feature.enabled: false)
k8s/deployment.yaml.tmpl      Deployment template (3 replicas, checksum + Reloader annotations)
k8s/service.yaml              ClusterIP Service
scripts/build-image.sh        Build (and optionally load) the image
scripts/deploy.sh             Apply namespace/ConfigMap/Service + rendered Deployment
scripts/render-deployment.sh  Recompute checksum/config and re-apply the Deployment
scripts/update-configmap.sh   Flip feature.enabled and kubectl apply the ConfigMap
scripts/observe.sh            Hit the Service from inside the cluster, N times, to see which pod answers
```

Scripts are bash (`envsubst`, `sha256sum`) — run them from Git Bash or WSL on
Windows. Every step also works as a plain `kubectl` command if you'd rather
run it by hand; those are given throughout.

## 0. Prerequisites

- A local cluster: `kind` or `minikube` (this whole walkthrough has been run
  end-to-end against `minikube`; `kind` works the same way).
- `kubectl`, `docker`, and (for the scripts) `envsubst` on PATH.
- Optional: [Stakater Reloader](https://github.com/stakater/Reloader) for the auto-rollout step (installed in step 7).

**Windows / Git Bash note**: Git Bash's MSYS layer rewrites POSIX-looking
arguments (`/config/...`) into Windows paths before they reach `kubectl` or
`docker`, which breaks commands like `kubectl exec ... -- cat /config/application.yaml`
or `docker run -v /host/path:/config`. If a command below fails with a
Windows-style path in the error message, prefix it with
`MSYS_NO_PATHCONV=1`, e.g.:
```bash
MSYS_NO_PATHCONV=1 kubectl exec -n configmap-rotations deploy/config-demo -- cat /config/application.yaml
```

## 1. Build the image and load it into the cluster

```bash
./scripts/build-image.sh minikube    # or: kind / none (if pushing to a real registry)
```

Equivalent by hand:

```bash
docker build -t config-demo:latest .
minikube image load config-demo:latest
# kind users: kind load docker-image config-demo:latest
```

## 2. Deploy: Namespace, ConfigMap, Service, Deployment (3 replicas)

```bash
./scripts/deploy.sh
```

Equivalent by hand:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/service.yaml

CONFIG_CHECKSUM=$(kubectl get configmap config-demo-config -n configmap-rotations -o jsonpath='{.data}' | sha256sum | cut -d' ' -f1)
envsubst < k8s/deployment.yaml.tmpl | kubectl apply -f -

kubectl rollout status deployment/config-demo -n configmap-rotations
kubectl get pods -n configmap-rotations -o wide
```

You should see 3 `Running` pods. On a busy or resource-constrained node,
Spring Boot's cold start can take well over a minute per pod (several JVMs
starting at once compete for CPU) — that's why `startupProbe` in
`k8s/deployment.yaml.tmpl` gives it a 180-second budget before giving up.
`kubectl rollout status` will just look like it's hanging; `kubectl get
events -n configmap-rotations --sort-by=.lastTimestamp` will show it's
actually progressing.

## 3. Confirm the "before" state

```bash
kubectl port-forward -n configmap-rotations svc/config-demo 8080:80
curl http://localhost:8080/feature
# {"feature.enabled":false,"pod":"config-demo-xxxxxxx","servedAt":"..."}
```

All 3 pods return `false`, matching the ConfigMap.

## 4. Update the ConfigMap: `feature.enabled=false` → `true`

```bash
./scripts/update-configmap.sh true
```

Equivalent by hand: edit `data.application.yaml` in `k8s/configmap.yaml`
(change `enabled: false` to `enabled: true`) and `kubectl apply -f k8s/configmap.yaml`,
or `kubectl edit configmap config-demo-config -n configmap-rotations` directly.

(`update-configmap.sh`'s `sed` is anchored to exactly 2-space indent so it
only ever touches the top-level `feature: / enabled:` line — worth knowing
if you add more `enabled:`-style keys anywhere else in that YAML, since an
unanchored replace would silently corrupt those too.)

### What happens immediately — ConfigMap propagation

The `ConfigMap` object in the API server updates instantly. Each node's
kubelet is watching the ConfigMaps used by its pods and updates the
projected volume file asynchronously — typically within a few seconds, but
not synchronized across pods/nodes, and **only because this demo mounts the
ConfigMap as a full volume, not with `subPath`** (a `subPath` mount is a
one-time bind copied at pod start and is *never* updated by kubelet, no
matter how long you wait — check inside a pod:

```bash
kubectl exec -n configmap-rotations deploy/config-demo -- cat /config/application.yaml
```

You'll see `enabled: true` on disk in every pod within roughly a minute.
Now hit the app again:

```bash
curl http://localhost:8080/feature
# still {"feature.enabled":false, ...}
```

**Still `false`.** The file changed; the running JVM did not re-read it.
Spring Boot binds `@Value` once, at bean creation — this app has no
`@RefreshScope`/config-watcher wired in, which is deliberate: it isolates
"file on disk changed" from "application observed the change" so you can
see the gap directly.

## 5. Rollout restart

```bash
kubectl rollout restart deployment/config-demo -n configmap-rotations
kubectl rollout status deployment/config-demo -n configmap-rotations
```

This replaces every pod (new pod template revision, even though nothing in
the template's fields actually changed — `rollout restart` forces a restart
by patching a timestamp annotation). New pods start, mount the volume fresh
(so they read `enabled: true` from the get-go), pass readiness, and old
pods terminate.

### Why some pods can briefly serve old values

While run:

```bash
./scripts/observe.sh 40 0.25
```

(This runs a short-lived curl pod inside the cluster hitting
`http://config-demo/feature` in a loop — deliberately *not*
`kubectl port-forward`, which sticks to a single backend pod for the whole
session and would never show you a mix of answers.)

During the rollout window you'll see a mix of `true` and `false` responses,
from different pod names. Three things combine to cause this:

1. **Rolling update overlap.** With `maxSurge: 1, maxUnavailable: 0`, old and
   new pods coexist and both receive traffic from the Service until the
   rollout finishes — that's the whole point of a rolling update (no
   downtime), but it means the answer depends on load-balancing luck.
2. **Per-node/per-pod propagation skew.** Even before any rollout, kubelet's
   ConfigMap-volume watch fires independently per node — it's eventually
   consistent, not atomic across the fleet. Two old pods on two different
   nodes can pick up the new file content seconds apart from each other.
3. **In-memory staleness independent of the file.** As shown in step 4, an
   old pod can have the *new* file on disk yet still answer with the *old*
   value, because it cached the value at startup. Only replacing the pod
   (not just updating the file) fixes this for that pod.

So "old value briefly served" isn't a bug — it's the union of a
deliberately-non-atomic rolling update and a deliberately-non-live-reloading
app. Production systems have to choose how to bound that window (next
section).

## 6. Checksum annotation (tie pod template to config content)

`k8s/deployment.yaml.tmpl` has:

```yaml
template:
  metadata:
    annotations:
      checksum/config: "${CONFIG_CHECKSUM}"
```

`scripts/render-deployment.sh` recomputes the checksum from the *live*
ConfigMap and re-applies:

```bash
./scripts/render-deployment.sh
```

Because the annotation lives on the **pod template**, changing it changes
the Deployment's pod template hash, which the Deployment controller treats
as a genuine spec change — it automatically starts a rolling update, with no
separate `kubectl rollout restart` needed. This is the same pattern Helm
charts use (`checksum/config: {{ include (print $.Template.BasePath
"/configmap.yaml") . | sha256sum }}`) to make config changes and pod
replacement inseparable by construction, instead of relying on someone to
remember to restart.

## 7. Stakater Reloader (fully automatic)

The Deployment already carries the opt-in annotation, and separately
references the ConfigMap by name in its volume — either one alone is enough
for Reloader to know to watch it (see "How Reloader knows what to watch"
below):

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
```

Install Reloader once per cluster (this creates a ServiceAccount, a
ClusterRole/ClusterRoleBinding with watch/patch access to
Deployments/StatefulSets/DaemonSets/ConfigMaps/Secrets cluster-wide, and a
single-replica Deployment — review the manifest if you're on a shared
cluster):

```bash
kubectl apply -f https://raw.githubusercontent.com/stakater/Reloader/master/deployments/kubernetes/reloader.yaml
# or: helm repo add stakater https://stakater.github.io/stakater-charts && helm install reloader stakater/reloader
```

The official manifest deploys it into the `default` namespace as
`deploy/reloader-reloader`. Confirm it's up:

```bash
kubectl get pods -n default -l app=reloader-reloader
```

With Reloader running, repeat step 4 (flip the ConfigMap) and **do nothing
else** — no `rollout restart`, no checksum script:

```bash
./scripts/update-configmap.sh false   # back to false, to see it trigger fresh
kubectl get pods -n configmap-rotations -w
```

Reloader watches ConfigMaps/Secrets referenced (or annotated) on workloads
and triggers the same "patch a restart annotation" rollout that
`kubectl rollout restart` does, automatically, within seconds of the
ConfigMap change. Check its work:

```bash
kubectl logs -n default deploy/reloader-reloader -f
```

You should see a line like:

```
level=info msg="Changes detected in 'config-demo-config' of type 'CONFIGMAP' in namespace 'configmap-rotations'; updated 'config-demo' of type 'Deployment' in namespace 'configmap-rotations'"
```

and `kubectl get pods -n configmap-rotations` will show a brand new
ReplicaSet rolling out within seconds of the ConfigMap edit, with no manual
trigger from you at all.

### How Reloader knows what to watch

Reloader doesn't watch every ConfigMap in the cluster — only ones actually
tied to a workload it can see, via either:

- the `reloader.stakater.com/auto: "true"` annotation on the workload
  (which then makes it watch whatever that workload references), or
- a direct reference: `spec.template.spec.volumes[].configMap.name` (our
  case — see `k8s/deployment.yaml.tmpl`'s `volumes:` block), or a
  container's `env[].valueFrom.configMapKeyRef` / `envFrom[].configMapRef`
  (this app doesn't use either of those, since `feature.enabled` only comes
  in through the mounted file, not an environment variable).

Checksum-annotation and Reloader solve the same problem two ways: the
checksum method is declarative and controller-free (works in any cluster,
tied to your CI/CD render step); Reloader is imperative and automatic
(works even if a human runs `kubectl edit`/`apply` directly against the
ConfigMap, which the checksum script can't catch unless it's re-run).
Running both is redundant but harmless — whichever fires first wins.

## 8. How to achieve consistent production rollouts

Ranked by robustness:

1. **Prefer immutable, hash-suffixed ConfigMaps over in-place edits.**
   Tools like Kustomize's `configMapGenerator` (or Helm's equivalent)
   create a *new* ConfigMap object per content change (e.g.
   `config-demo-config-8f92kt426t`) and rewrite the Deployment's volume
   reference to point at it, instead of editing `config-demo-config` in
   place as this repo's base manifests do.

   This is strictly the safest option because there is no "file changes
   under a running pod" phase at all — old pods keep mounting the old
   ConfigMap object unchanged until they're replaced, and replacement is a
   normal, fully-controlled rolling update. It also sidesteps the
   `subPath`-never-updates footgun entirely, since nothing is ever mutated
   in place. Not wired up in this repo (it's a `k8s/configmap.yaml` you
   edit directly), but worth knowing as the more robust alternative.

2. **If you must mutate a ConfigMap in place, always pair it with a forced
   rollout** — checksum annotation (step 6) or Reloader (step 7) — so a
   config change and a pod replacement are never two separate manual steps
   that someone can forget to do together.

3. **Use `readinessProbe` and `maxUnavailable: 0` / `maxSurge: 1`** (already
   set in `k8s/deployment.yaml.tmpl`) so the Service never routes traffic to
   a pod that hasn't finished starting with the new config, and capacity
   never dips during the rollout.

4. **Never use `subPath` for a ConfigMap volume you intend to hot-update** —
   it silently never refreshes; use a full volume mount as in this repo, or
   accept that `subPath` mounts require a pod replacement for every change
   regardless of any propagation mechanism.

5. **If the brief inconsistency window is unacceptable and restarts are
   expensive**, look at true dynamic reload instead of pod replacement:
   Spring Cloud Kubernetes' Config Watcher + `@RefreshScope` re-binds
   `@Value`/`@ConfigurationProperties` beans in place when it detects a
   ConfigMap change, without restarting the JVM. It's a different trade-off
   (added complexity, a `/actuator/refresh` round trip, and it's still
   eventually consistent across replicas) rather than a strictly better one
   — not wired into this demo on purpose, so the gap in step 4 stays
   visible.

## Troubleshooting

Issues actually hit while running this demo end-to-end on minikube, in case
you hit the same ones:

- **Pods crash-loop right after `kubectl apply`, `startupProbe failed:
  connection refused`.** Spring Boot's cold start is slower than it looks in
  a quiet local `docker run` — 10-15s in isolation, 30-45s or more when
  several replicas' JVMs start at once and compete for CPU on the node.
  Without a generous `startupProbe` (this repo uses 60 x 3s = 180s), the
  `livenessProbe` can kill the container mid-boot before it ever gets a
  chance to come up, which looks like a crash loop but is really just an
  impatient probe. `kubectl logs <pod>` (not `--previous`) will show Spring
  Boot happily still starting.
- **A probe check returns `404` instead of failing to connect.** This means
  the port is open and the app is serving requests, but that specific path
  isn't mapped — check `kubectl exec <pod> -- wget -qO- http://localhost:8080/actuator/health`
  and compare its output (specifically the `"groups"` key) against a
  healthy pod's. If `management.endpoint.health.probes.enabled` ever ends
  up `false` in the ConfigMap, Spring Boot stops exposing the
  `/actuator/health/liveness` and `/readiness` sub-paths entirely — which is
  exactly why this repo's probes target plain `/actuator/health` instead
  (see the comment above the probes in `k8s/deployment.yaml.tmpl`).
- **`kubectl exec ... -- cat /config/application.yaml` or `docker run -v
  /host:/config` fails with a path like `C:/Program Files/Git/config/...`
  in the error.** That's Git Bash's MSYS path-conversion mangling the
  argument — see the Windows note in Prerequisites (`MSYS_NO_PATHCONV=1`).
- **The mounted file only updates for full volume mounts.** If you ever
  switch `k8s/deployment.yaml.tmpl`'s `volumeMounts` to use `subPath`
  (e.g. to mount just `application.yaml` instead of the whole `/config`
  directory), kubelet stops updating that file on ConfigMap changes
  entirely, silently — no error, it just never refreshes.

## Cleanup

```bash
kubectl delete namespace configmap-rotations
# if installed: kubectl delete -f https://raw.githubusercontent.com/stakater/Reloader/master/deployments/kubernetes/reloader.yaml
```
