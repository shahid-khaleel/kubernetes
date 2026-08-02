# EKS IRSA with S3 Access

This document describes how to grant an Amazon EKS workload access to an S3 bucket using **IAM Roles for Service Accounts (IRSA)**. The flow is: create an S3 IAM policy → create an IAM role trusted by the EKS OIDC provider → attach the policy → bind the role to a Kubernetes ServiceAccount.

---

## 1. S3 IAM Policy

This policy allows basic object operations on the `testdata` bucket and permission to list the bucket.

**s3-policy.json**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::data/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::data"
    }
  ]
}
```

Create the policy:

```bash
aws iam create-policy \
  --policy-name s3-app-policy \
  --policy-document file://s3-policy.json
```

---

## 2. Get EKS OIDC Provider

Retrieve the OIDC issuer URL for the cluster:

```bash
aws eks describe-cluster \
  --name cluster \
  --region ap-south-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

Example output:

```
https://oidc.eks.ap-south-1.amazonaws.com/id/CADD145A9000F
```

Verify that the OIDC provider exists in IAM:

```bash
aws iam list-open-id-connect-providers
```

Example:

```
arn:aws:iam::12345:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/CADD145A9000F
```

---

## 3. IAM Role Trust Policy (IRSA)

The trust policy allows **only** the specified Kubernetes ServiceAccount to assume the role using web identity.

**trust.json**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::12345:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/CADD145A9000F"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "arn:aws:iam::12345:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/CADD145A9000F:sub": "system:serviceaccount:s3-app:s3-app-sa"
        }
      }
    }
  ]
}
```

Create the IAM role:

```bash
aws iam create-role \
  --role-name s3-app-irsa-role \
  --assume-role-policy-document file://trust.json
```

---

## 4. Attach S3 Policy to the Role

```bash
aws iam attach-role-policy \
  --role-name s3-app-irsa-role \
  --policy-arn arn:aws:iam::12345:policy/s3-app-policy
```

---

## 5. Kubernetes ServiceAccount

Create a ServiceAccount annotated with the IAM role ARN.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-app-sa
  namespace: s3-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::12345:role/s3-app-irsa-role
```

Apply it:

```bash
kubectl apply -f serviceaccount.yaml
```

---

## 6. Application Usage

* Pods using this ServiceAccount will automatically receive temporary AWS credentials.
* No AWS access keys are stored in Kubernetes secrets.
* The application can access S3 using the AWS SDK with the default credential provider chain.

---

## 7. Verification

Inside a pod using the ServiceAccount:

```bash
aws sts get-caller-identity
```

Expected result: the ARN should show `assumed-role/s3-app-irsa-role`.

---

## Summary

This setup follows least-privilege principles:

* Scoped S3 permissions
* Namespace- and ServiceAccount-specific role assumption
* Short-lived credentials via IRSA
