# Kubernetes API Request Flow — Hands-On Labs

What actually happens between `kubectl apply` and a Pod existing on the
cluster. Each stage below is a real, working lab against this Minikube
cluster — not just theory.

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
Webhook (OPA/Kyverno)
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

## Stage-by-stage

### 1. Authentication — "Who are you?"

The API server verifies the caller's identity: a client certificate, a
bearer token (ServiceAccount token, OIDC token, etc.), or (if enabled)
falling back to `system:anonymous`. It does **not** care yet what you're
allowed to do — only whether it can determine who is asking.

- Fails → `401 Unauthorized`, request stops here entirely.
- Succeeds → the request carries an identity (a username and group set)
  into the next stage.

**Lab:** `scripts/01-test-authentication.sh` sends a raw request with a
garbage bearer token directly to the API server and gets back `401`.

### 2. Authorization (RBAC) — "Are you allowed to do THIS?"

Now that the API server knows *who* you are, it checks whether that
identity is allowed to perform the specific verb (get/list/create/delete/…)
on the specific resource, in the specific namespace. This is RBAC: Roles /
ClusterRoles define permission sets, RoleBindings / ClusterRoleBindings
attach them to identities.

- Fails → `403 Forbidden`, request stops here.
- Succeeds → proceeds to admission.

**Lab:** `scripts/02-test-authorization.sh` creates a `viewer`
ServiceAccount that can only `get/list/watch` pods, mints it a real token,
and proves the boundary: listing pods succeeds, creating one is denied.

### 3. Admission Controllers — built-in policy and defaulting

Compiled-in plugins that run on every write request (create/update/delete),
*after* authorization. Two kinds:

- **Mutating** — can modify the object before it's persisted (e.g.
  `LimitRanger` injecting default resource requests/limits,
  `DefaultStorageClass` filling in a PVC's storage class).
- **Validating** — can only allow/deny, no modification (e.g.
  `ResourceQuota` rejecting a pod that would exceed a namespace's quota,
  `NamespaceLifecycle` rejecting objects in a terminating namespace).

These are compiled into `kube-apiserver` itself — no separate deployment,
no network hop. (This is the key difference from stage 4.)

**Lab:** `scripts/03-test-admission-controller.sh` covers both:
(a) a pod with no `resources:` block gets defaults injected by `LimitRanger`
(mutating), and (b) a second pod is rejected once a `ResourceQuota` of
`pods: "1"` is exhausted (validating).

### 4. Webhook (OPA / Kyverno) — custom, cluster-specific policy

Dynamic admission webhooks are **not** compiled into the API server — they're
ordinary pods running in your cluster (Kyverno, OPA Gatekeeper, etc.) that
the API server calls out to over HTTPS for every matching request, via a
`ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration` you
register. This is how organizations enforce custom rules ("every pod must
have an owner label", "no `:latest` image tags", "no privileged
containers") without patching Kubernetes itself.

Same allow/deny (and optionally mutate) semantics as built-in admission
controllers, just implemented outside the API server binary and reachable
over the network — which is also why webhook availability/latency matters
operationally (a hung webhook can block *all* matching requests cluster-wide).

**Lab:**
- `scripts/00-install-kyverno.sh` installs Kyverno (one-time, ~1-2 min).
- `scripts/04-test-webhook-policy.sh` applies a `ClusterPolicy` requiring a
  `team` label on every Pod in the `webhook-demo` namespace, then proves it:
  a pod missing the label is blocked with Kyverno's custom message; a pod
  with the label sails through and is created — completing the full pipeline
  down to "Pod Created".

### 4b. The same policy, via OPA Gatekeeper instead

Kyverno and OPA Gatekeeper both plug into the exact same slot in the
pipeline (a `ValidatingWebhookConfiguration`), so the diagram's
"Webhook (OPA/Kyverno)" really means "pick one" — most clusters only run
one of the two. This project installs **both**, scoped to different
namespaces, purely so you can compare how each expresses the identical rule:

| | Kyverno | OPA Gatekeeper |
|---|---|---|
| Policy language | YAML (`pattern` matching) | Rego (a real query language) |
| Object | `ClusterPolicy` | `ConstraintTemplate` (reusable rule) + `Constraint` (a parameterized instance of it) |
| Learning curve | Low — declarative, reads like the object it validates | Higher — Rego has its own syntax/semantics to learn |
| Reuse across rules | Copy/adapt YAML per policy | One `ConstraintTemplate` can back many `Constraint` instances with different `parameters` |
| Namespace here | `webhook-demo` | `opa-demo` |

**Lab:**
- `scripts/05-install-opa-gatekeeper.sh` installs Gatekeeper (one-time,
  ~1-2 min).
- `scripts/06-test-opa-policy.sh` applies a `ConstraintTemplate`
  (`k8srequiredlabels`, generic — takes a `labels` parameter) and a
  `Constraint` (`require-team-label-opa`, parameterized with
  `labels: ["team"]`) scoped to the `opa-demo` namespace, then proves the
  same blocked/allowed behavior as the Kyverno demo, via a completely
  different policy engine.

## Running the labs, in order

```bash
bash scripts/01-test-authentication.sh
bash scripts/02-test-authorization.sh
bash scripts/03-test-admission-controller.sh
bash scripts/00-install-kyverno.sh        # one-time, takes a minute or two
bash scripts/04-test-webhook-policy.sh
bash scripts/05-install-opa-gatekeeper.sh # one-time, takes a minute or two
bash scripts/06-test-opa-policy.sh
```

## Files

```
manifests/
  01-rbac-viewer-sa.yaml            ServiceAccount + Role (pod-reader) + RoleBinding
  02-test-pod.yaml                  Pod used to test the 'viewer' identity's create attempt
  03-admission-namespace.yaml       Namespace for the built-in admission controller demo
  04-limitrange.yaml                LimitRange -- default cpu/mem (mutating admission)
  05-resourcequota.yaml             ResourceQuota -- pods: "1" (validating admission)
  06-bare-pod.yaml                  Pod with no resources -- gets LimitRange defaults injected
  07-bare-pod-2.yaml                Second pod -- blocked once quota is exhausted
  08-kyverno-require-team-label.yaml Kyverno ClusterPolicy requiring a 'team' label
  09-webhook-demo-namespace.yaml    Namespace for the Kyverno demo
  10-pod-missing-label.yaml         Pod without 'team' label -- blocked by the webhook
  11-pod-with-label.yaml            Pod with 'team' label -- allowed, Pod Created
  12-opa-demo-namespace.yaml        Namespace for the OPA Gatekeeper demo
  13-gatekeeper-constrainttemplate.yaml Rego rule: object must carry given labels
  14-gatekeeper-constraint.yaml     Instance of the rule: Pods in opa-demo need 'team'
  15-pod-missing-label-opa.yaml     Pod without 'team' label -- blocked by Gatekeeper
  16-pod-with-label-opa.yaml        Pod with 'team' label -- allowed, Pod Created
scripts/
  00-install-kyverno.sh             One-time Kyverno install
  01-test-authentication.sh         Stage 1 demo
  02-test-authorization.sh          Stage 2 demo (writes .generated/viewer.kubeconfig)
  03-test-admission-controller.sh   Stage 3 demo
  04-test-webhook-policy.sh         Stage 4 demo (Kyverno)
  05-install-opa-gatekeeper.sh      One-time OPA Gatekeeper install
  06-test-opa-policy.sh             Stage 4 demo (OPA Gatekeeper) -- same rule, compare to Kyverno
```

`.generated/` is created at runtime by `02-test-authorization.sh` (holds a
throwaway kubeconfig for the `viewer` ServiceAccount) — safe to delete
between runs.

## Cleanup

```bash
kubectl delete -f manifests/01-rbac-viewer-sa.yaml
kubectl delete namespace admission-demo
kubectl delete namespace webhook-demo
kubectl delete clusterpolicy require-team-label
kubectl delete -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl delete namespace opa-demo
kubectl delete k8srequiredlabels require-team-label-opa
kubectl delete constrainttemplate k8srequiredlabels
kubectl delete -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
rm -rf .generated
```

## Notes

- Kyverno's install manifest must be applied with `--server-side` (see
  `scripts/00-install-kyverno.sh`) -- its two largest CRDs exceed the size
  limit `kubectl apply`'s client-side `last-applied-configuration` annotation
  allows. This is a known Kyverno issue on any cluster, not Minikube-specific.
- `system:anonymous` requests can look "authenticated" through `kubectl` if
  your local kubeconfig still has valid credentials cached for the current
  context -- kubectl merges flag overrides with existing config rather than
  fully replacing it. `scripts/01-test-authentication.sh` uses a raw `curl`
  request instead, to guarantee no local credentials leak into the test.
- `kubectl wait` requires the target resource to already exist -- it errors
  immediately with `NotFound` rather than polling for creation. Gatekeeper
  creates a Constraint's backing CRD asynchronously after you apply its
  `ConstraintTemplate`, so `scripts/06-test-opa-policy.sh` polls for the
  CRD's existence in a loop before calling `kubectl wait` on it.
