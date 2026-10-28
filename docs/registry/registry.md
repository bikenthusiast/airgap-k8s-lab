# Lab registry on airgap-lab-infra

## Overview

| | |
|---|---|
| Software | `docker-registry` 2.8.3+ds1-2build1 (CNCF distribution), Ubuntu package |
| Service | `docker-registry.service`, runs as user `docker-registry`, enabled at boot |
| Address | `https://airgap-lab-infra:5000` (also `https://10.10.10.10:5000`) |
| Config | `/etc/docker/registry/config.yml` (copy in this repo: [`infra/registry-config.yml`](../../infra/registry-config.yml)) |
| Storage | `/var/lib/docker-registry` (143 MB as of 2026-10-28) |
| TLS | `/etc/docker/registry/tls/` (750 root:docker-registry): `registry.crt` (644 root:root), `registry.key` (640 root:docker-registry) |
| Certificate | serial `3520E9C2D2EB09FCF8C4314FC51DE94A952C9BB9`, valid until **2027-10-21 16:59:49 UTC**, SAN `DNS:airgap-lab-infra, IP:10.10.10.10`, issued by airgap-lab Root CA (public copy: [`pki/registry.crt`](../../pki/registry.crt)) |
| Mirroring tool | `skopeo` 1.21.0~pre1-2build1 |

## Mirrored images

Kubernetes v1.37.1, list from `kubeadm config images list`: [`images-v1.37.1.txt`](images-v1.37.1.txt)
Paths keep the upstream layout: `registry.k8s.io/X` → `airgap-lab-infra:5000/X`, amd64 only.

## Clients

- CA trusted system-wide on infra, cp1, w1, w2 (`/usr/local/share/ca-certificates/airgap-lab-ca.crt`, `update-ca-certificates`).
- containerd on cp1, w1, w2 mirrors `registry.k8s.io` to this registry via `/etc/containerd/certs.d/registry.k8s.io/hosts.toml` (see [`scripts/node-prep.sh`](../../scripts/node-prep.sh)).
- containerd must be restarted after the CA changes (Go reads the trust store at start).

## Health checks

```bash
systemctl is-active docker-registry
curl https://airgap-lab-infra:5000/v2/            # {} + 200
curl https://airgap-lab-infra:5000/v2/_catalog
sudo journalctl -u docker-registry -n 30 --no-pager
```

## Mirroring more images

```bash
REG=airgap-lab-infra:5000
while read -r img; do
  skopeo copy --retry-times 3 "docker://$img" "docker://$REG/${img#registry.k8s.io/}"
done < images.txt
```

## Certificate renewal (expires 2027-10-21)

1. Create a new key and CSR in `/srv/registry/tls`, sign with the CA, check with `openssl verify`.
2. Copy `registry.crt` and `registry.key` to `/etc/docker/registry/tls` (same modes and owners as above).
3. `sudo systemctl restart docker-registry`
4. Check from a node: `curl https://airgap-lab-infra:5000/v2/` → 200; new serial: `openssl s_client -connect airgap-lab-infra:5000 </dev/null | openssl x509 -noout -serial -enddate`
5. Update `pki/registry.crt`, the table in `docs/ca/ca.md` and this file.

## Failure mode

Registry down → new pods `ErrImagePull` / `ImagePullBackOff`; running pods are unaffected because their images are cached on the nodes (see Defekt 18). The registry is a single point of failure for the air-gapped cluster.
