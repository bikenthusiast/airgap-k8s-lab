# bundle/ — the offline bundle (milestone M3)

> **Status:** concept. The build process is implemented in M3.

## Purpose

The bundle is the **only** way software enters the air gap. It is built in the
online zone (on the Mac), copied to `infra` through the data diode, verified
there, and only then used.

Its sole input is `versions.yaml`: whatever is not pinned there does not go
into the bundle.

## Planned layout

```
bundle/out/airgap-bundle-<YYYYMMDD>-<git-sha>/
├── manifest.yaml        copy of versions.yaml + build metadata (time, commit)
├── debs/
│   ├── amd64/           kubeadm, kubelet, kubectl, chrony, dnsmasq … with deps
│   └── arm64/
├── binaries/
│   ├── amd64/           containerd, runc, CNI plugins, crictl, helm, zot
│   └── arm64/
├── images/              container images as an OCI layout (multi-arch)
├── charts/              Helm charts (e.g. Cilium) as .tgz
├── SHA256SUMS           checksums of every file
└── SHA256SUMS.sig       signature over the checksums
```

## Planned workflow

1. **Build (Mac, online):** download packages, binaries, images
   (`skopeo copy --all` or `crane`) and charts according to `versions.yaml`.
   The list of Kubernetes component images comes from
   `kubeadm config images list --kubernetes-version <version>`.
2. **Seal:** generate `SHA256SUMS` and sign it.
3. **Transfer:** `scp` through the data diode to `infra` (192.168.56.10).
   No shared folder.
4. **Verify (infra, offline):** check signature and checksums. On any mismatch,
   nothing is installed.
5. **Publish:** packages into the local APT repository, images and charts into
   the registry (Zot).

## Things that matter

- **Multi-arch from day one** (ADR-0009): the Mac is amd64, the Pis are arm64.
  Images are copied with all platforms, otherwise they will not start on the
  other architecture later.
- **Do not forget the sandbox image:** the `pause` image that containerd needs
  for every pod must be in the bundle.
- Build tools (skopeo, crane) run on the Mac, e.g. via Homebrew or in a
  container (Colima/Docker).
- `bundle/out/` is in `.gitignore`: bundles are large and reproducible from
  `versions.yaml` at any time.
