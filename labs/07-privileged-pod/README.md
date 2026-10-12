# 07 · A privileged Kubernetes pod

**Scenario:** "the API couldn't reach Redis" and "permission denied": someone fixes both in
`deploy/k8s/base/api.yaml` with `hostNetwork: true` and `privileged: true`, and drops the security context.
**Caught by:** Trivy (misconfiguration scanner on the Kubernetes manifests), in the prescan job.

```bash
labs/plant.sh 07
git show
```

## What you should see

```text
| Trivy fs (CRITICAL,HIGH) | 4 (vuln 0, misconfig 4, secret 0) | 0 without a fix yet, 19 at lower severity, ... |

Blocking findings:
  trivy       HIGH KSV-0009  Access to host network  (deploy/k8s/base/api.yaml)
  trivy       HIGH KSV-0014  Root file system is not read-only  (deploy/k8s/base/api.yaml)
  trivy       HIGH KSV-0017  Privileged  (deploy/k8s/base/api.yaml)
  trivy       HIGH KSV-0118  Default security context configured  (deploy/k8s/base/api.yaml)
```

(The extra MEDIUM findings, such as "runs as root" and "can elevate its own privileges", are in the report too.)

## Things to notice

- A privileged container is effectively root **on the node**. `hostNetwork` puts it on the node's network,
  bypassing network policies. Both "fixes" hid the real problems (a missing Service, a wrong file permission).
- Infrastructure-as-code is code: the same pull-request gate reviews it before it reaches a cluster.

## Fix it

Restore the security context (`runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`,
`capabilities: drop: ["ALL"]`, `seccompProfile: RuntimeDefault`), and fix the original problems properly.

<details><summary>Reference fix</summary>

`labs/fix.sh 07` reverts the change.
</details>

**Done?** `labs/reset.sh`
