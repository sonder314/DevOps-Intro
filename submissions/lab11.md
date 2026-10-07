# Lab 11 — Reproducible Builds of QuickNotes with Nix

I built QuickNotes and its container image from one locked Nix flake. I then compared independent Nix builds with conventional Docker builds and added a CI gate that performs the reproducibility check on two fresh runners.

## Task 1 — Reproducible Go Build

### Implementation

My root [`flake.nix`](../flake.nix) pins the `nixos-25.11` input, exposes `quicknotes` and `default`, disables CGO, passes `-s -w` to the Go linker, and provides a development shell with Go, `gopls`, and `golangci-lint`. The exact nixpkgs commit and content hash are recorded in [`flake.lock`](../flake.lock).

I used `buildGoModule` because QuickNotes is a standard Go module and does not need the extra generated expression used by `buildGoApplication`. QuickNotes imports only the standard library. Consequently, `go mod vendor` produces an empty dependency tree and current nixpkgs requires the explicit `vendorHash = null` form; a non-null fake hash fails with `vendor folder is empty`. There are no unpinned module downloads.

### Build and runtime evidence

Environment A:

```text
quicknotes> Building subPackage ./.
quicknotes> Running phase: checkPhase
quicknotes> ok          quicknotes      0.007s
store_a=/nix/store/xkc8pyi23fin676zsd7q22bgj08hmmlz-quicknotes-0.1.0
hash_a=sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k
```

Environment B (fresh Nix store):

```text
quicknotes_store_b=/nix/store/xkc8pyi23fin676zsd7q22bgj08hmmlz-quicknotes-0.1.0
quicknotes_hash_b=sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k
```

Runtime proof:

```text
2026/10/07 17:53:47 quicknotes listening on 127.0.0.1:18080 (notes loaded: 4)
{"notes":4,"status":"ok"}
```

The two independent store hashes are identical: `sha256:1hv80kblj0zqcz82z0wihvxz63kylgwkqqgv5naykf0ar4f26w8k`.

### Design questions

#### a) Why can plain `go build` differ between machines?

Plain builds may use different Go toolchains, resolved module contents, environment paths, VCS metadata, and build IDs. Timestamps can also enter surrounding artifacts. A Git SHA identifies the source tree, but it does not identify this complete build environment. Nix declares and locks those inputs, while `CGO_ENABLED=0`, fixed linker flags, and Go's deterministic compiler remove host-library variation.

#### b) What does `vendorHash` cover, and what does `null` mean?

`vendorHash` is the recursive SHA-256 of the fixed-output derivation produced after `go mod vendor`, so it authenticates the complete fetched module source tree rather than only `go.mod`. With `vendorHash = null`, `buildGoModule` does not create that dependency-fetching derivation and instead expects either no external modules or an already vendored tree. That is the correct explicit value here because QuickNotes has no external modules; nixpkgs rejects a non-null hash for an empty vendor result.

#### c) Why is `flake.lock` essential?

`flake.nix` selects a moving channel name, whereas `flake.lock` records the exact nixpkgs revision and Nar hash. That revision determines Go, `buildGoModule`, `dockerTools`, and their transitive build tools. Deleting the lock file lets Nix resolve the channel again, so a later build can use different inputs, produce a different store path, or fail.

#### d) Why did I choose `buildGoModule`?

`buildGoModule` is the nixpkgs-native two-stage builder: it handles module dependencies as a fixed-output derivation and then builds in the sandbox. `buildGoApplication` is a flake-parts helper from `nixpkgs-build-system` that generates package expressions and is useful for larger multi-package flake layouts. QuickNotes is one small module with no external dependencies, so `buildGoModule` is the simpler, auditable choice.

## Task 2 — Deterministic OCI Image

### Implementation and runtime

The `docker` output uses `dockerTools.buildImage`, includes the Task 1 package, sets `Entrypoint` to `/bin/quicknotes`, declares `8080/tcp`, and runs as `nonroot:nonroot` (UID/GID 65532). Its creation timestamp is fixed. The writable data file is placed under `/tmp`, which is mode `1777`; the application itself and seed are read-only. No Docker daemon participates in this image build.

```text
Loaded image: quicknotes:nix
{"notes":4,"status":"ok"}
user=nonroot:nonroot entrypoint=["/bin/quicknotes"] ports={"8080/tcp":{}}
```

### Independent digest proof

Environment A:

```text
0504125c2cbb10c967f9858adfff66392161e711e340ed82e60e1f802b055149  result
size_bytes=3163782
```

Environment B (fresh Nix store):

```text
0504125c2cbb10c967f9858adfff66392161e711e340ed82e60e1f802b055149  /nix/store/hkb8ffrgy2drlcqk2l6ivva3bvp1clqc-docker-image-quicknotes.tar.gz
```

Both tarballs have SHA-256 `0504125c2cbb10c967f9858adfff66392161e711e340ed82e60e1f802b055149`.

### Comparison with the Lab 6 Dockerfile

```text
run1 id=sha256:cde07357d424ee6dbfe78aa274b57f3e88f85403c5950a332c65a9c872af82d3
     size=8238416 created=2026-10-07T15:00:42.229090582Z
run2 id=sha256:e596937b98f3c025d214c2427572d01d25448768bbff7148dce52f7dcbccf4b8
     size=8238416 created=2026-10-07T15:01:02.986822406Z
```

| Artifact | Size | Independent build identity |
|---|---:|---|
| Nix image tarball | 3,163,782 bytes (3.1 MiB) | `0504125c2cbb10c967f9858adfff66392161e711e340ed82e60e1f802b055149` in both environments |
| Lab 6 Docker image, run 1 | 8,238,416 bytes (7.9 MiB) | `sha256:cde07357d424ee6dbfe78aa274b57f3e88f85403c5950a332c65a9c872af82d3` |
| Lab 6 Docker image, run 2 | 8,238,416 bytes (7.9 MiB) | `sha256:e596937b98f3c025d214c2427572d01d25448768bbff7148dce52f7dcbccf4b8` |

#### e) What makes a conventional Docker build non-deterministic?

Docker records image configuration and layer metadata, including timestamps, and mutable base-image tags can resolve to new content. Package repositories, network downloads, generated files, filesystem ordering, and builder versions are additional undeclared inputs. A clean cache does not lock or normalize them; it only forces those operations to happen again.

#### f) What extra claim can a security auditor verify?

A signature proves who approved one image digest, but not that the image corresponds to the reviewed source. With a reproducible image, an auditor can independently rebuild the same Git revision and lock file and compare digests. Equality provides evidence that the distributed artifact was produced from the declared inputs without an undisclosed build-time modification.

#### g) What is the trade-off?

Nix gives strong isolation and dependency pinning, but it adds a language, store model, tooling, disk usage, and maintenance cost. Some build systems also need patches to work without network access. Dockerfiles remain more common because the mental model, registries, CI integrations, and operational skills are already widespread, even though their default reproducibility guarantees are weaker.

### Reproducibility issue found during verification

My first cross-environment image comparison failed even though the executable NAR hashes matched. The Git flake input excluded local helper directories while the explicit path input retained empty directories, so the package received a different input-addressed store path; that path was then present inside the image. I replaced the broad source filter with `lib.fileset.fileFilter`, which includes only `go.mod`, `go.sum` when present, and `.go` files and omits empty directories. A local Git-versus-path check and the final fresh-container build then produced the same image SHA-256.

## Bonus — CI-Verified Reproducibility

The [`nix-repro.yml`](../.github/workflows/nix-repro.yml) workflow starts two independent Ubuntu runners in parallel. Each installs the same SHA-pinned Nix action, builds `.#docker`, and exports the tarball digest. A third job compares the outputs and fails on missing or unequal values.

- Deliberately broken red run: https://github.com/sonder314/DevOps-Intro/actions/runs/37652698651
- Corrected green run: PENDING_GREEN_RUN_URL

Matching green-run excerpt:

```text
PENDING_CI_DIGESTS
```

#### h) Why is CI evidence load-bearing?

Repeated local builds may silently share the same Nix store, binary cache, machine configuration, or uncommitted files. CI rebuilds the committed revision on disposable infrastructure and leaves an immutable, reviewable log. An auditor can therefore connect the reproducibility claim to the exact repository state instead of trusting my workstation.

#### i) Why use two parallel jobs?

Two jobs start with separate runners and stores. Building twice in one job can return the already-built store path or reuse local state, so it mainly verifies cache lookup rather than independent construction. Parallel jobs also avoid ordering effects between the first and second build.

#### j) How is `SOURCE_DATE_EPOCH` relevant here?

Timestamps could leak through generated source, Go linker inputs, image configuration, or tar metadata. This application does not embed a build time, and `dockerTools.buildImage` normalizes the filesystem archive while I explicitly set the image `created` value to a constant. Therefore the image digest does not depend on wall-clock time or `SOURCE_DATE_EPOCH`.

## Conclusion

The local and disposable-container builds produced identical QuickNotes NAR hashes and identical image tarball SHA-256 digests. The conventional Dockerfile produced different image IDs from two no-cache builds because its creation metadata changed. CI evidence below independently repeats the Nix image comparison on two fresh hosted runners.
