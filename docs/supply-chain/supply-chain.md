# Supply-chain controls

Image signing and admission-time verification for the air-gapped cluster, fully offline.

## Versions

| Component | Version |
|---|---|
| Kubernetes | v1.37.1 |
| Kyverno | v1.20.0 (supported range 1.34–1.37) |
| cosign | v2.6.5 |
| syft | v1.57.1 |

## How an image gets into the cluster

1. **Mirror** on `airgap-lab-infra` (the only host with internet): `skopeo copy` into `airgap-lab-infra:5000`. Only the amd64 variant is copied, so the digest differs from upstream.
2. **Sign by digest** after mirroring: `cosign sign --key /srv/cosign/cosign.key --tlog-upload=false <image>@sha256:…`. The signature is stored in the registry as tag `sha256-<digest>.sig`.
3. **Attest the SBOM:** `syft` creates an SPDX SBOM, `cosign attest --type spdxjson` attaches it as a signed attestation (`.att`). Example: `sbom-demo-nginx.spdx.json`.
4. **Verify at admission:** Kyverno `ImageValidatingPolicy` (`../../policies/verify-lab-image-signatures.yaml`) checks the signature with `cosign.pub` and rewrites the tag to the digest.

No transparency log in the air gap: signing with `--tlog-upload=false`, verification with `insecureIgnoreTlog` / `insecureIgnoreSCT`.

## Keys

- Private key: `/srv/cosign/cosign.key` on infra only (mode 600, password-protected). **Never in this repo.** In production: KMS/HSM.
- Public key: `cosign.pub` (this folder), embedded in the policy.

## Policy

- Kind `ImageValidatingPolicy` (`policies.kyverno.io/v1`). Kyverno v1.20 no longer accepts the legacy `kyverno.io/v1 ClusterPolicy` with `verifyImages`.
- Scope: namespace `supply-chain-demo` only, images `airgap-lab-infra:5000/demo/*`.
- `validationActions: [Deny]`, `mutateDigest`, `verifyDigest`, `required`, `failurePolicy: Fail`.

## Cluster prerequisites

- **Kyverno trusts the lab CA:** ConfigMap `lab-ca-bundle` (node trust bundle) mounted into `kyverno-admission-controller`, `SSL_CERT_FILE=/etc/ssl/lab/ca-bundle.crt`.
- **Pods resolve infra names:** CoreDNS has no `forward` (no upstream in the air gap). `hosts` plugin entry `10.10.10.10 airgap-lab-infra` (`coredns.yaml`). Without it, Kyverno fails with `lookup airgap-lab-infra on 10.96.0.10:53: server misbehaving`.

## Test results (2026-11-13)

| Test | Result |
|---|---|
| Signed image | allowed, pinned to `@sha256:bb8f72…c7` |
| Unsigned image | denied |
| Tag moved to other content | denied (`no signatures found`); running pod unaffected (pinned) |
| Signed with a foreign key | denied |
| Other namespace | unaffected |
| Kyverno down (graceful) | **admitted**, see below |

## Finding: fail-closed config, fail-open behaviour

On a graceful shutdown (scale to 0) the Kyverno admission controller **deletes its webhook configurations** (10 → 2; `kyverno-resource-validating-webhook-cfg` gone) and recreates them on start. With no webhook registered, the API server admitted an unsigned image in 0.3 s despite `failurePolicy: Fail`.

Mitigations:
- ≥ 2 replicas, PodDisruptionBudget, anti-affinity across nodes
- Alert on admission-controller availability and on missing webhook configurations
- Defence in depth: only signed, approved images enter the internal registry; the registry ingestion is the primary trust boundary, Kyverno the second layer

Open: a hard crash (`kill -9`, node power-off) probably leaves the webhooks registered (fail-closed). To be tested.

## Runbook

- **Lab CA renewed:** rebuild ConfigMap `lab-ca-bundle`, restart `kyverno-admission-controller`. Otherwise every deployment in scope fails with `x509`.
- **Key rotation:** add the new key as a second attestor, re-sign images, then remove the old key.
- **New image:** mirror → sign by digest → attest SBOM → deploy.
- **Kyverno upgrade:** check release notes for removed APIs and the Kubernetes compatibility range first.
