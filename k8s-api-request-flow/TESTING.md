# Testing Guide

Step-by-step commands for each stage of the request flow, with actual output
captured from real runs against this Minikube cluster — so you can compare
your own run against a known-good result. Covers `dev`, `staging`, and
`prod` since each behaves differently (quota size, policy enforcement mode).

Run everything from the project root (`k8s-api-request-flow/`). `[env]`
defaults to `dev` if omitted from any script.

---

## Prerequisites

```bash
minikube status
kubectl get nodes
```

Both should show a running, `Ready` cluster before starting.

---

## One-time: install Kyverno

```bash
bash scripts/00-install-kyverno.sh
```

Takes ~1-2 minutes. If you see:
```
Error from server (Invalid): ... metadata.annotations: Too long: may not be
more than 262144 bytes
```
see [Troubleshooting](#troubleshooting) — the script already handles this
with `--server-side`.

---

## Per environment: deploy

```bash
bash scripts/01-deploy.sh dev
```

**Actual output:**

```
== Deploying overlays/dev ==
namespace/k8s-flow-dev created
resourcequota/pod-count-quota created
serviceaccount/viewer created
role.rbac.authorization.k8s.io/pod-reader created
rolebinding.rbac.authorization.k8s.io/viewer-pod-reader created
limitrange/default-resources created

== Deploying overlays/dev/cluster-policy (requires Kyverno installed) ==
clusterpolicy.kyverno.io/require-team-label-dev created

Namespace k8s-flow-dev is ready.
```

Repeat with `staging` / `prod` as needed — all three can coexist (separate
namespaces).

**Preview without touching the cluster:**

```bash
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod/cluster-policy
```

---

## Stage 1 — Authentication

```bash
bash scripts/02-test-authentication.sh
```

Environment-independent — a raw HTTP call, not a Kubernetes object. Safe to
run before any deploy.

**Actual output:**

```
API server: https://127.0.0.1:XXXXX

== Raw request with an invalid bearer token ==
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
}
HTTP_STATUS:401
```

**Pass condition:** `HTTP_STATUS:401`. If you instead see a list of pods,
your shell's `kubectl`/`KUBECONFIG` credentials are leaking into the test —
see [Troubleshooting](#troubleshooting).

---

## Stage 2 — Authorization (RBAC)

```bash
bash scripts/03-test-authorization.sh dev
```

**Actual output:**

```
== Minting a short-lived token for 'viewer' in k8s-flow-dev ==
Wrote .generated/viewer-dev.kubeconfig

== As 'viewer': GET pods in k8s-flow-dev (allowed by the Role) ==
No resources found in k8s-flow-dev namespace.

== As 'viewer': CREATE a pod in k8s-flow-dev (NOT allowed by the Role) ==
Error from server (Forbidden): error when creating "fixtures/test-pod.yaml":
pods is forbidden: User "system:serviceaccount:k8s-flow-dev:viewer" cannot
create resource "pods" in API group "" in the namespace "k8s-flow-dev"
```

**Pass condition:** the `get pods` succeeds; the `create` fails with
`Forbidden ... cannot create resource "pods"`. Same result in every
environment — RBAC doesn't vary by env here.

---

## Stage 3 — Admission Controllers (built-in)

```bash
bash scripts/04-test-admission-controller.sh dev
```

Quota size differs per environment (dev=3, staging=2, prod=1), so the
script fills any remaining headroom with labeled filler pods first, then
always attempts exactly one pod over the actual limit — the outcome is the
same shape in every environment, just with a different number.

**Actual output (dev, limit 3):**

```
== Clearing any pods left over from a previous run (keeps this script order-independent) ==

== (a) MUTATING: creating a pod with NO resources specified, in k8s-flow-dev ==
pod/bare-pod created

-- What actually got created (resources injected by LimitRanger) --
{"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}

== (b) VALIDATING: filling remaining quota headroom, then exceeding it by one ==
Quota: 1/3 pods currently used in k8s-flow-dev.
Created 2 filler pod(s) to consume remaining headroom.

-- Now attempting bare-pod-2, one pod over the 3-pod limit --
Error from server (Forbidden): error when creating "fixtures/bare-pod-2.yaml":
pods "bare-pod-2" is forbidden: exceeded quota: pod-count-quota, requested:
pods=1, used: pods=3, limited: pods=3
```

**Actual output (prod, limit 1 — no filler pods needed):**

```
== (b) VALIDATING: filling remaining quota headroom, then exceeding it by one ==
Quota: 1/1 pods currently used in k8s-flow-prod.
Created 0 filler pod(s) to consume remaining headroom.

-- Now attempting bare-pod-2, one pod over the 1-pod limit --
Error from server (Forbidden): error when creating "fixtures/bare-pod-2.yaml":
pods "bare-pod-2" is forbidden: exceeded quota: pod-count-quota, requested:
pods=1, used: pods=1, limited: pods=1
```

**Pass condition:** `bare-pod`'s resources show injected `limits`/`requests`
even though `fixtures/bare-pod.yaml` specified none; `bare-pod-2` is
rejected with `exceeded quota`, with `used`/`limited` matching that
environment's actual quota.

---

## Stage 4 — Webhook (Kyverno)

```bash
bash scripts/05-test-webhook-policy.sh dev
```

**dev runs the policy in `Audit` mode — it does NOT block:**

```
Policy require-team-label-dev is in 'Audit' mode.
(dev only enforces this policy in Audit mode -- non-compliant pods are
 logged/reported but NOT blocked. staging/prod use Enforce, which blocks.)

== Pod WITHOUT the required 'team' label ==
pod/no-team-label created

== Pod WITH the required 'team' label ==
pod/has-team-label created
```

**staging/prod run in `Enforce` mode — it blocks:**

```bash
bash scripts/05-test-webhook-policy.sh prod
```

```
Policy require-team-label-prod is in 'Enforce' mode.

== Pod WITHOUT the required 'team' label ==
Error from server: error when creating "fixtures/pod-missing-label.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/k8s-flow-prod/no-team-label was blocked due to the following policies

require-team-label-prod:
  check-team-label: 'validation error: Every pod must have a ''team'' label so we
    know who owns it. rule check-team-label failed at path /metadata/labels/'

== Pod WITH the required 'team' label ==
pod/has-team-label created
```

**Pass condition:** in `dev`, both pods are created (check
`kubectl get policyreport -n k8s-flow-dev` to confirm the violation was
still recorded even though nothing was blocked). In `staging`/`prod`,
`no-team-label` is rejected by `admission webhook "validate.kyverno.svc-fail"`
with the custom policy message; `has-team-label` is created in all three.

---

## Troubleshooting

**Stage 1 shows pod list instead of 401.**
You ran `kubectl --token=... get pods` instead of the raw `curl` in the
script. `kubectl` merges flag overrides with your existing kubeconfig rather
than fully replacing it, so it silently falls back to your real
client-certificate credentials. Always test raw authentication with `curl`
directly against the API server, not through `kubectl`.

**Kyverno install fails with `metadata.annotations: Too long`.**
Re-run with `--server-side --force-conflicts`:
```bash
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
```
Client-side `kubectl apply` embeds the entire object into a
`last-applied-configuration` annotation; Kyverno's `clusterpolicies.kyverno.io`
and `policies.kyverno.io` CRDs are large enough to exceed the 262144-byte
annotation limit. Server-side apply doesn't use that annotation at all.

**Stage 3's bare-pod gets blocked by the Kyverno webhook instead of
demonstrating LimitRange/ResourceQuota.**
This happens in `staging`/`prod` (Enforce mode) if `fixtures/bare-pod.yaml`
or `bare-pod-2.yaml` lose their `team: platform` label — the Enforce-mode
policy applies to every pod in the namespace, not just the webhook demo's
own fixtures. Both files already carry the label for this reason; if you
add new fixtures, label them too.

**Stage 4 policy doesn't block anything in staging/prod.**
Give it a few seconds after `01-deploy.sh` applies the `ClusterPolicy` —
Kyverno's webhook configuration needs a moment to register the new rule.
Confirm with `kubectl get clusterpolicy require-team-label-<env> -o yaml`
and check `status.conditions`, and confirm
`spec.validationFailureAction` is actually `Enforce` for that environment.

**`kubectl create token` fails ("unknown command").**
Requires Kubernetes 1.24+ (`kubectl create token <serviceaccount>`). Check
with `kubectl version`; this cluster runs a version that supports it.

**A `Namespace` resource doesn't get `-dev`/`-staging`/`-prod` appended to
its name even though `nameSuffix` is set.**
This is a real Kustomize limitation (verified against v5.8.1), not a bug in
this repo — `nameSuffix`/`namePrefix` don't apply to `Namespace` objects.
That's why each overlay defines its own explicitly-named `namespace.yaml`
instead of relying on suffix behavior.

---

## Full run, start to finish (one environment)

```bash
bash scripts/00-install-kyverno.sh
bash scripts/01-deploy.sh dev
bash scripts/02-test-authentication.sh
bash scripts/03-test-authorization.sh dev
bash scripts/04-test-admission-controller.sh dev
bash scripts/05-test-webhook-policy.sh dev
```

Swap `dev` for `staging`/`prod` (steps 2 onward) to see the same pipeline
behave differently under stricter policy/quota.

## Cleanup after testing

```bash
for env in dev staging prod; do
  kubectl delete -k "overlays/${env}/cluster-policy" --ignore-not-found=true
  kubectl delete -k "overlays/${env}" --ignore-not-found=true
done
kubectl delete -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
rm -rf .generated
```
