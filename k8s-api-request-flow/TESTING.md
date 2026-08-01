# Testing Guide

Step-by-step commands for each stage of the request flow, with the actual
output captured from a real run against this Minikube cluster — so you can
compare your own run against a known-good result.

Run everything from the project root (`k8s-api-request-flow/`).

---

## Prerequisites

```bash
minikube status
kubectl get nodes
```

Both should show a running, `Ready` cluster before starting.

---

## Stage 1 — Authentication

```bash
bash scripts/01-test-authentication.sh
```

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
see [Troubleshooting](#troubleshooting) below.

---

## Stage 2 — Authorization (RBAC)

```bash
bash scripts/02-test-authorization.sh
```

**Actual output:**

```
== Applying ServiceAccount + Role + RoleBinding ==
serviceaccount/viewer created
role.rbac.authorization.k8s.io/pod-reader created
rolebinding.rbac.authorization.k8s.io/viewer-pod-reader created

== Minting a short-lived token for the 'viewer' ServiceAccount ==
Wrote .generated/viewer.kubeconfig

== As 'viewer': GET pods (allowed by the Role) ==
NAME        READY   STATUS    RESTARTS   AGE
mysql-a-0   1/1     Running   0          26m
mysql-b-0   1/1     Running   0          35m

== As 'viewer': CREATE a pod (NOT allowed by the Role) ==
Error from server (Forbidden): error when creating "manifests/02-test-pod.yaml":
pods is forbidden: User "system:serviceaccount:default:viewer" cannot create
resource "pods" in API group "" in the namespace "default"
```

**Pass condition:** the `get pods` succeeds; the `create` fails with
`Forbidden ... cannot create resource "pods"`.

**Manual variant**, without a real token, using impersonation:

```bash
kubectl auth can-i get pods --as=system:serviceaccount:default:viewer
# yes
kubectl auth can-i create pods --as=system:serviceaccount:default:viewer
# no
```

---

## Stage 3 — Admission Controllers (built-in)

```bash
bash scripts/03-test-admission-controller.sh
```

**Actual output:**

```
== Setting up namespace, LimitRange, ResourceQuota ==
namespace/admission-demo created
limitrange/default-resources created
resourcequota/pod-count-quota created

== (a) MUTATING: creating a pod with NO resources specified ==
pod/bare-pod created

-- What actually got created (resources injected by LimitRanger) --
{"limits":{"cpu":"250m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}

== (b) VALIDATING: creating a second pod when quota only allows 1 ==
Error from server (Forbidden): error when creating "manifests/07-bare-pod-2.yaml":
pods "bare-pod-2" is forbidden: exceeded quota: pod-count-quota, requested:
pods=1, used: pods=1, limited: pods=1
```

**Pass condition:** `bare-pod`'s resources show injected `limits`/`requests`
even though `06-bare-pod.yaml` specified none; `bare-pod-2` is rejected with
`exceeded quota`.

**Inspect manually:**

```bash
kubectl get pod bare-pod -n admission-demo -o yaml | grep -A6 resources:
kubectl describe resourcequota pod-count-quota -n admission-demo
```

---

## Stage 4 — Webhook (Kyverno)

### 4a. Install (one-time)

```bash
bash scripts/00-install-kyverno.sh
```

Takes ~1-2 minutes. Confirms readiness by waiting on all pods in the
`kyverno` namespace, then prints the registered webhook:

```
validatingwebhookconfigurations.admissionregistration.k8s.io/kyverno-resource-validating-webhook-cfg   ...
```

If you see:
```
Error from server (Invalid): ... metadata.annotations: Too long: may not be
more than 262144 bytes
```
that's Kyverno's two largest CRDs exceeding the `kubectl apply`
client-side annotation limit — the script already uses `--server-side` to
avoid this (see [Troubleshooting](#troubleshooting)).

### 4b. Policy test

```bash
bash scripts/04-test-webhook-policy.sh
```

**Actual output:**

```
== Setting up namespace + Kyverno ClusterPolicy ==
namespace/webhook-demo created
clusterpolicy.kyverno.io/require-team-label created

== Pod WITHOUT the required 'team' label ==
Error from server: error when creating "manifests/10-pod-missing-label.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/webhook-demo/no-team-label was blocked due to the following policies

require-team-label:
  check-team-label: 'validation error: Every pod must have a ''team'' label so we
    know who owns it. rule check-team-label failed at path /metadata/labels/'

== Pod WITH the required 'team' label ==
pod/has-team-label created
```

**Pass condition:** `no-team-label` is rejected by
`admission webhook "validate.kyverno.svc-fail"` with the custom policy
message; `has-team-label` is created successfully.

**Inspect manually:**

```bash
kubectl get clusterpolicy require-team-label
kubectl get pods -n webhook-demo
kubectl get validatingwebhookconfigurations | grep kyverno
```

---

## Stage 4b — Webhook (OPA Gatekeeper), same policy as Kyverno's

### Install (one-time)

```bash
bash scripts/05-install-opa-gatekeeper.sh
```

Takes ~1-2 minutes.

### Policy test

```bash
bash scripts/06-test-opa-policy.sh
```

**Actual output:**

```
== Setting up namespace + ConstraintTemplate + Constraint ==
namespace/opa-demo created
constrainttemplate.templates.gatekeeper.sh/k8srequiredlabels created

Waiting for Gatekeeper to generate the ConstraintTemplate's CRD...
customresourcedefinition.apiextensions.k8s.io/k8srequiredlabels.constraints.gatekeeper.sh condition met
k8srequiredlabels.constraints.gatekeeper.sh/require-team-label-opa created

== Pod WITHOUT the required 'team' label ==
Error from server (Forbidden): error when creating "manifests/15-pod-missing-label-opa.yaml":
admission webhook "validation.gatekeeper.sh" denied the request:
[require-team-label-opa] you must provide labels: {"team"}

== Pod WITH the required 'team' label ==
pod/has-team-label-opa created
```

**Pass condition:** `no-team-label-opa` is rejected by
`admission webhook "validation.gatekeeper.sh"` with
`you must provide labels: {"team"}`; `has-team-label-opa` is created.

**Compare side by side with Kyverno's result** (Stage 4 above) — same rule,
same outcome, two different policy engines and two different error message
formats. Notice the webhook name in the error differs
(`validate.kyverno.svc-fail` vs `validation.gatekeeper.sh`) — that's your
signal for which engine actually blocked a given request when both are
installed cluster-wide.

**Inspect manually:**

```bash
kubectl get constrainttemplate k8srequiredlabels
kubectl get k8srequiredlabels require-team-label-opa -o yaml
kubectl get pods -n opa-demo
kubectl get validatingwebhookconfigurations | grep gatekeeper
```

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

**Stage 4 policy doesn't block anything.**
Give it a few seconds after `kubectl apply`-ing the `ClusterPolicy` —
Kyverno's webhook configuration needs a moment to register the new rule.
Confirm with `kubectl get clusterpolicy require-team-label -o yaml` and check
`status.conditions`.

**`kubectl create token` fails ("unknown command").**
Requires Kubernetes 1.24+ (`kubectl create token <serviceaccount>`). Check
with `kubectl version`; this cluster runs a version that supports it.

**`kubectl wait` on the Gatekeeper CRD fails with `NotFound`.**
`kubectl wait` requires the resource to already exist — it does not poll for
creation. Gatekeeper creates the Constraint's backing CRD asynchronously
after the `ConstraintTemplate` is applied, which can take a couple seconds.
`scripts/06-test-opa-policy.sh` already polls for the CRD's existence before
calling `kubectl wait`; if you're doing this manually, add a short retry
loop around `kubectl get crd k8srequiredlabels.constraints.gatekeeper.sh`
first.

---

## Full run, start to finish

```bash
bash scripts/01-test-authentication.sh
bash scripts/02-test-authorization.sh
bash scripts/03-test-admission-controller.sh
bash scripts/00-install-kyverno.sh
bash scripts/04-test-webhook-policy.sh
bash scripts/05-install-opa-gatekeeper.sh
bash scripts/06-test-opa-policy.sh
```

## Cleanup after testing

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
