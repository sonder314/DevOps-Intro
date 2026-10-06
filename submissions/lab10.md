# Lab 10 — Cloud Computing: Shipping QuickNotes

I published QuickNotes to GitHub Container Registry through a tag-driven release workflow and deployed the same release image to a public Render free web service. I used Render Option A because signup did not require a card for the free service.

## Task 1 — CI-automated push to GHCR

### Release workflow

The complete workflow is in [`.github/workflows/release.yml`](../.github/workflows/release.yml). It triggers for `v*.*.*` tags, builds `app/` for `linux/amd64`, and publishes both the immutable release tag and `latest`.

The workflow grants no default permissions. Its publish job grants only:

```yaml
permissions:
  contents: read
  packages: write
```

Every external action is pinned by a full 40-character commit SHA:

```text
actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
docker/setup-buildx-action@6524bf65af31da8d45b59e8c27de4bd072b392f5
docker/login-action@9780b0c442fbb1117ed29e0efdff1e18412f7567
docker/build-push-action@ca877d9245402d1537745e0e356eab47c3520991
```

Release evidence:

- Signed tags: `v0.1.0` and `v0.1.1`
- Registry image: `ghcr.io/sonder314/devops-intro/quicknotes`
- Immutable tags: `v0.1.0` and `v0.1.1`
- Convenience tag: `latest`
- [Successful v0.1.0 release run](https://github.com/sonder314/DevOps-Intro/actions/runs/36871072481)
- [Release workflow history, including the v0.1.1 Render deployment](https://github.com/sonder314/DevOps-Intro/actions/workflows/release.yml)
- [Anonymous pull output](evidence/lab10/ghcr-pull.txt)

I performed the pull with an empty `DOCKER_CONFIG`, so no registry credentials were available. The public pull completed with this digest:

```text
Digest: sha256:417a7e606af7416e180bd76990132dcbcda546bc94cd67b7beadf3519cb30786
Status: Downloaded newer image for ghcr.io/sonder314/devops-intro/quicknotes:v0.1.0
```

### Design questions

#### a) When would I use OIDC instead of `GITHUB_TOKEN`?

`GITHUB_TOKEN` is sufficient for publishing a package owned by the same GitHub repository. I would use OIDC when deploying to an external cloud such as AWS, Azure, or Google Cloud. OIDC exchanges a short-lived, signed workflow identity for narrowly scoped cloud credentials. This avoids storing a long-lived cloud access key in GitHub and lets the cloud verify the repository, branch, workflow, and environment that requested access.

#### b) Why publish both `latest` and an immutable version tag?

`latest` is a convenient discovery and development pointer for users who intentionally want the newest release. The version tag gives deployments, rollbacks, incident investigations, and audits a stable reference. Production configuration should use the version tag or digest, while `latest` remains a human-friendly convenience.

#### c) Why grant only `packages: write`?

This follows least privilege. A compromised build action needs to read source and publish a package; it does not need permission to modify source, releases, issues, pull requests, or other repository settings. Granting `write: all` would let the same compromise tamper with additional repository assets and make persistence or supply-chain attacks more damaging.

## Task 2 — Render deployment

### Configuration and automated deployment

I deployed the public GHCR image as a Render **Free** web service in Frankfurt. The full configuration and persistence expectations are documented in [`cloud/render.md`](../cloud/render.md).

- Public service: <https://quicknotes-lab10-5vo7.onrender.com>
- Source: existing public GHCR image
- Health check: `/health`
- `PORT=8080`
- `ADDR=0.0.0.0:8080`
- `DATA_PATH=/data/notes.json`
- `SEED_PATH=/app/seed.json`

I stored the Render deploy hook only in the GitHub Actions secret `RENDER_DEPLOY_HOOK_URL`. After publishing a tag, the workflow appends the URL-encoded tag through `imgURL` and calls the hook. The successful `v0.1.1` workflow completed the **Trigger Render deployment** step, changing the service from `v0.1.0` to `v0.1.1` without exposing the hook.

Render deploy log excerpt ([full evidence](evidence/lab10/render-deploy-log.txt)):

```text
2026/10/06 08:32:16 quicknotes listening on 0.0.0.0:8080 (notes loaded: 4)
2026/10/06 08:47:23 shutting down
2026/10/06 08:54:39 quicknotes listening on 0.0.0.0:8080 (notes loaded: 4)
```

The process listened on the configured port immediately; the log contains no `New primary port detected` restart. The later stop/start pairs also corroborate the spin-down measurements.

### Public health check

The complete evidence is in [`health-curl-verbose.txt`](evidence/lab10/health-curl-verbose.txt) and [`health-body.json`](evidence/lab10/health-body.json).

```text
> GET /health HTTP/2
< HTTP/2 200
< content-type: application/json
< server: cloudflare
< x-render-origin-server: Render

{"notes":4,"status":"ok"}
```

The later `GET /notes` also returned the four seed notes, proving that both required endpoints were public.

### Warm and cold latency

I used [`scripts/lab10-measure.sh`](../scripts/lab10-measure.sh). The raw measurements are in [`latency.csv`](evidence/lab10/latency.csv). The table below uses the final five-request warm series taken after the CI deployment.

| Measurement | Total time |
|---|---:|
| Warm 1 | 0.520388 s |
| Warm 2 | 0.489452 s |
| Warm 3 | 0.494494 s |
| Warm 4 | 1.748168 s |
| Warm 5 | 0.618555 s |
| **Warm p50** | **0.520388 s** |
| Cold 1, after 28+ min idle | 12.781654 s |
| Cold 2, after 22+ min idle | 13.891225 s |
| Cold 3, after 21+ min idle | 13.072699 s |

The first cold request was about 24.6 times slower than warm p50 because Render had to wake the service before forwarding the request.

### Ephemeral note test

Before the first spin-down, I created this note:

```json
{"id":5,"title":"ephemeral-render-note","body":"created before spin-down"}
```

After more than 20 minutes idle, the cold request woke the service. `GET /notes` then returned only the four original seed notes; note `id=5` was absent. The before and after responses are saved in [`note-created.json`](evidence/lab10/note-created.json) and [`notes-after-cold.json`](evidence/lab10/notes-after-cold.json).

### Design questions

#### d) Why is Render wake-up slower than Cloud Run scale-to-zero?

Render's free tier optimizes for low cost and can fully stop the service on shared infrastructure. A wake may require scheduling capacity, starting the container, and restoring routing. Cloud Run is designed for request-driven production workloads and invests in a faster scheduler, cached artifacts, and warm platform capacity. Render provides free general hosting; Cloud Run optimizes for rapid elastic request handling.

#### e) Why does Render inject `PORT` instead of trusting `EXPOSE`?

`EXPOSE` is image metadata and does not guarantee that a process actually listens on that port. Render needs a runtime port for its proxy and health checks, so it supplies `PORT`. I set both `PORT=8080` and `ADDR=0.0.0.0:8080`. If they differed, Render would detect the actual port and restart the deploy, adding roughly another deployment cycle and repeating that cost on later mismatched releases.

#### f) Why deploy an existing image, and where did the note go?

Using the existing image gives artifact parity: Render runs the same tagged image built by CI, anonymously pulled for verification, and based on the hardened container from Lab 9. It is faster and more reproducible than rebuilding independently. A Render source build can provide platform-native build logs and caching, but it creates another build whose bytes may differ from the scanned release.

The note was written to `/data/notes.json` on the container's ephemeral filesystem. Render replaced the stopped instance during wake-up, so the new container started from the image's seed data. A production deployment would store notes in an external database or persistent managed storage.

## Verification summary

- Signed tag triggered the release workflow: **passed**.
- Public anonymous GHCR pull: **passed**.
- SHA-pinned actions and least-privilege permissions: **passed**.
- CI deploy hook updated Render to `v0.1.1`: **passed**.
- Public `/health` and `/notes`: **passed**.
- Warm p50 and three cold samples: **recorded**.
- Ephemeral note-loss behavior: **demonstrated**.

## Bonus

I did not attempt the optional Cloudflare Tunnel bonus. The mandatory 10-point scope is complete.
