# Render deployment configuration

I use a Render **Web Service** backed by the exact public image produced by the release workflow.

Public service URL: <https://quicknotes-lab10-5vo7.onrender.com>

| Setting | Value |
|---|---|
| Source | Existing Image |
| Initial image URL | `ghcr.io/sonder314/devops-intro/quicknotes:v0.1.0` |
| Current image URL | `ghcr.io/sonder314/devops-intro/quicknotes:v0.1.1` (selected by the CI deploy hook) |
| Region | Frankfurt (EU Central) |
| Instance type | Free |
| Health check path | `/health` |
| `PORT` | `8080` |
| `ADDR` | `0.0.0.0:8080` |
| `DATA_PATH` | `/data/notes.json` |
| `SEED_PATH` | `/app/seed.json` |

I set both `PORT` and `ADDR` to port 8080 before the first deploy. Render therefore routes to the same port on which QuickNotes listens and does not need a second deploy after detecting a different primary port.

I chose an existing image rather than a Render source build so that the deployed bytes are the same `linux/amd64` artifact built by GitHub Actions, scanned in Lab 9, tagged for the release, and verified with an anonymous pull.

## Automated deployment

I copied the service's deploy hook from Render and stored it in the GitHub repository secret `RENDER_DEPLOY_HOOK_URL`. The release workflow appends an URL-encoded `imgURL` containing the pushed tag and calls the hook only after the image push succeeds. The hook itself is never committed.

## Persistence expectation

The free service has an ephemeral filesystem. QuickNotes writes notes to `/data/notes.json` inside the container, so notes can disappear whenever Render replaces or restarts the instance, including during a cold wake. This deployment is suitable for the lab but would need an external database or persistent storage for production data.
