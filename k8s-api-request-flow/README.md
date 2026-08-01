# Kubernetes API Request Flow — Hands-On Labs

What actually happens between `kubectl apply` and a Pod existing on the
cluster. Each stage below is a real, working lab against this Minikube
cluster — not just theory. Structured as a production-style Kustomize
repo: a shared `base/`, promoted through `dev` → `staging` → `prod`
overlays with real per-environment differences.

## The Flow

```
kubectl apply
      │
      ▼
  API Server
      │
Authentication
      │
Authorization (RBAC)
      │
Admission Controllers
      │
Webhook (Kyverno)
      │
   Allowed?
      │
      ▼
 Pod Created
```

Every single request to the Kubernetes API — not just `kubectl apply`, *any*
call, from any client — passes through this same pipeline. A request can be
rejected at any stage, and once rejected it never proceeds further down the
chain.

## Folder structure

```
base/
  namespaced/          RBAC (viewer SA/Role/RoleBinding), LimitRange,
                        ResourceQuota -- the persistent scaffolding.
                        No `namespace:` set -- each overlay decides.
  cluster-policy/       The Kyverno ClusterPolicy. Kept in its OWN
                        kustomization, separate from base/namespaced,
                        because it's cluster-scoped -- see Notes.
fixtures/               Standalone test pods (NOT part of any
                        kustomization). Applied on-demand by the test
                        scripts with an explicit `-n <namespace>`, not
                        as permanent base state -- see Notes.
overlays/
  dev/                  namespace: k8s-flow-dev,  quota: 3 pods, policy: Audit
  staging/               namespace: k8s-flow-staging, quota: 2 pods, policy: Enforce
  prod/                  namespace: k8s-flow-prod,  quota: 1 pod,  policy: Enforce
  <env>/cluster-policy/  per-env ClusterPolicy (suffixed name, patched
                          target namespace + enforcement mode)
scripts/                 Deploy + one script per pipeline stage
```

Why `fixtures/` isn't part of `base/`: several of these pods exist purely to
demonstrate one stage getting blocked (an over-quota pod, a mislabeled pod).
If they were permanent base state, they'd all compete for the same
`ResourceQuota` and break each other (this happened during development —
see Notes). Real production repos draw the same line: durable
infrastructure lives in `base/`+`overlays/`; one-off test/debug objects do
not.

## Stage-by-stage

### 1. Authentication — "Who are you?"

The API server verifies the caller's identity: a client certificate, a
bearer token (ServiceAccount token, OIDC token, etc.), or (if enabled)
falling back to `system:anonymous`. It does **not** care yet what you're
allowed to do — only whether it can determine who is asking.

- Fails → `401 Unauthorized`, request stops here entirely.
- Succeeds → the request carries an identity (a username and group set)
  into the next stage.

**Lab:** `scripts/02-test-authentication.sh` sends a raw request with a
garbage bearer token directly to the API server and gets back `401`.
Environment-independent — no deploy needed first.

### 2. Authorization (RBAC) — "Are you allowed to do THIS?"

Now that the API server knows *who* you are, it checks whether that
identity is allowed to perform the specific verb (get/list/create/delete/…)
on the specific resource, in the specific namespace. This is RBAC: Roles /
ClusterRoles define permission sets, RoleBindings / ClusterRoleBindings
attach them to identities.

- Fails → `403 Forbidden`, request stops here.
- Succeeds → proceeds to admission.

**Lab:** `scripts/03-test-authorization.sh [dev|staging|prod]` mints a real
token for the `viewer` ServiceAccount (deployed by `01-deploy.sh`, scoped to
`get/list/watch` pods only) and proves the boundary: listing pods succeeds,
creating one is denied.

### 3. Admission Controllers — built-in policy and defaulting

Compiled-in plugins that run on every write request (create/update/delete),
*after* authorization. Two kinds:

- **Mutating** — can modify the object before it's persisted (e.g.
  `LimitRanger` injecting default resource requests/limits).
- **Validating** — can only allow/deny, no modification (e.g.
  `ResourceQuota` rejecting a pod that would exceed a namespace's quota).

These are compiled into `kube-apiserver` itself — no separate deployment,
no network hop. (This is the key difference from stage 4.)

**Lab:** `scripts/04-test-admission-controller.sh [dev|staging|prod]`
covers both: (a) a pod with no `resources:` block gets defaults injected by
`LimitRanger` (mutating), and (b) it fills any remaining quota headroom with
filler pods, then always attempts exactly one pod over the environment's
limit (`ResourceQuota` — validating). Quota size differs per environment
(dev=3, staging=2, prod=1), which is why the script computes headroom
dynamically instead of assuming a fixed number.

### 4. Webhook (Kyverno) — custom, cluster-specific policy

Dynamic admission webhooks are **not** compiled into the API server — they're
an ordinary pod running in your cluster (Kyverno, in this project) that the
API server calls out to over HTTPS for every matching request, via a
`ValidatingWebhookConfiguration` you register. This is how organizations
enforce custom rules ("every pod must have an owner label", "no `:latest`
image tags", "no privileged containers") without patching Kubernetes itself.

Same allow/deny semantics as built-in admission controllers, just
implemented outside the API server binary and reachable over the network —
which is also why webhook availability/latency matters operationally (a hung
webhook can block *all* matching requests cluster-wide).

**This project runs the SAME policy at different strictness per
environment** — a real production pattern:

| Environment | `validationFailureAction` | Effect |
|---|---|---|
| `dev` | `Audit` | Violations are logged (`PolicyReport`), pod is still created — doesn't block iteration |
| `staging` | `Enforce` | Violations are blocked, same as prod, so issues surface before prod |
| `prod` | `Enforce` | Violations are blocked |

**Lab:** `scripts/00-install-kyverno.sh` installs Kyverno once (one-time,
~1-2 min). `scripts/05-test-webhook-policy.sh [dev|staging|prod]` creates a
pod missing the `team` label and one with it, and reports what actually
happened based on that environment's enforcement mode.

## Running the labs

```bash
bash scripts/00-install-kyverno.sh          # one-time, takes a minute or two

bash scripts/01-deploy.sh dev               # deploys namespace/RBAC/quota + ClusterPolicy for dev
bash scripts/02-test-authentication.sh      # env-independent
bash scripts/03-test-authorization.sh dev
bash scripts/04-test-admission-controller.sh dev
bash scripts/05-test-webhook-policy.sh dev

bash scripts/01-deploy.sh staging           # repeat for staging / prod
bash scripts/03-test-authorization.sh staging
bash scripts/04-test-admission-controller.sh staging
bash scripts/05-test-webhook-policy.sh staging

bash scripts/01-deploy.sh prod
bash scripts/03-test-authorization.sh prod
bash scripts/04-test-admission-controller.sh prod
bash scripts/05-test-webhook-policy.sh prod
```

All three environments can be deployed simultaneously (they live in
separate namespaces) — useful for comparing `kubectl get policyreport -n
k8s-flow-dev` (violations logged, not blocked) against prod's hard rejection
side by side.

Preview what any overlay will actually create, without touching the
cluster:

```bash
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod/cluster-policy
```

## Files

```
base/
  namespaced/
    kustomization.yaml   No `namespace:` field -- set per overlay
    viewer-sa.yaml        ServiceAccount + Role (pod-reader) + RoleBinding
    limitrange.yaml        Default cpu/mem (mutating admission)
    resourcequota.yaml     pods: "1" (base default; overlays patch per env)
  cluster-policy/
    kustomization.yaml     No `namespace:` field -- ClusterPolicy is cluster-scoped
    cluster-policy.yaml    Requires a 'team' label on Pods
fixtures/
  test-pod.yaml           Used by stage 2 -- the create the 'viewer' identity attempts
  bare-pod.yaml           Used by stage 3(a) -- no resources: block, needs team label to pass stage 4
  bare-pod-2.yaml         Used by stage 3(b) -- the pod that goes one-over quota
  pod-missing-label.yaml  Used by stage 4 -- no 'team' label
  pod-with-label.yaml     Used by stage 4 -- has 'team' label
overlays/
  dev/kustomization.yaml            namespace: k8s-flow-dev, quota patched to 3
  dev/namespace.yaml
  dev/cluster-policy/kustomization.yaml   ClusterPolicy suffixed -dev, Audit mode, targets k8s-flow-dev
  staging/  ...same shape, quota 2, Enforce, targets k8s-flow-staging
  prod/     ...same shape, quota 1, Enforce, targets k8s-flow-prod
scripts/
  00-install-kyverno.sh             One-time Kyverno install
  01-deploy.sh [env]                Deploys overlays/<env> + overlays/<env>/cluster-policy
  02-test-authentication.sh         Stage 1 demo (env-independent)
  03-test-authorization.sh [env]    Stage 2 demo (writes .generated/viewer-<env>.kubeconfig)
  04-test-admission-controller.sh [env]  Stage 3 demo
  05-test-webhook-policy.sh [env]   Stage 4 demo
```

`[env]` defaults to `dev` in every script if omitted.

`.generated/` is created at runtime by `03-test-authorization.sh` (holds a
throwaway kubeconfig per environment) — gitignored, safe to delete.

## Cleanup

```bash
kubectl delete -k overlays/dev/cluster-policy
kubectl delete -k overlays/dev
kubectl delete -k overlays/staging/cluster-policy
kubectl delete -k overlays/staging
kubectl delete -k overlays/prod/cluster-policy
kubectl delete -k overlays/prod
kubectl delete -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
rm -rf .generated
```

## Notes

- **Kyverno's install manifest must be applied with `--server-side`** (see
  `scripts/00-install-kyverno.sh`) — its two largest CRDs exceed the size
  limit `kubectl apply`'s client-side `last-applied-configuration` annotation
  allows. This is a known Kyverno issue on any cluster, not Minikube-specific.
- **`system:anonymous` requests can look "authenticated" through `kubectl`**
  if your local kubeconfig still has valid credentials cached for the
  current context — kubectl merges flag overrides with existing config
  rather than fully replacing it. `scripts/02-test-authentication.sh` uses a
  raw `curl` request instead, to guarantee no local credentials leak into
  the test.
- **`kubectl kustomize` does not apply `nameSuffix`/`namePrefix` to
  `Namespace` resources themselves** (verified empirically against
  kustomize v5.8.1 bundled with kubectl) — a real limitation, not a
  misconfiguration. This is why each overlay defines its own explicitly
  named `namespace.yaml` (`k8s-flow-dev`, etc.) rather than relying on a
  shared base Namespace plus a suffix.
- **Kustomize's `namespace:` transformer can't tell a CRD is cluster-scoped**
  and will incorrectly inject `metadata.namespace` into a `ClusterPolicy` if
  it's combined into the same kustomization as namespaced resources. This is
  why `cluster-policy/` is always its own separate kustomization, applied
  with a second `kubectl apply -k`, never folded into the main overlay.
- **Fixture pods intentionally aren't part of the declarative base.** Early
  in development they were, and having `bare-pod`/`bare-pod-2` (admission
  demo) and `has-team-label`/`no-team-label` (webhook demo) all
  permanently co-resident in one namespace meant they exhausted each
  other's `ResourceQuota` before either demo could run. Once Enforce-mode
  policy is live cluster-wide for a namespace (staging/prod), it also
  applies to `bare-pod`/`bare-pod-2` themselves — they carry a `team` label
  for exactly this reason, even though their actual purpose is unrelated
  to the label-policy demo.
