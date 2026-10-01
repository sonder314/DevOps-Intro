---
title: QuickNotes
emoji: 📝
colorFrom: blue
colorTo: green
sdk: docker
app_port: 8080
pinned: false
short_description: A small hardened Go notes API deployed for DevOps Lab 10.
---

# QuickNotes

I deploy the exact `ghcr.io/sonder314/devops-intro/quicknotes:v0.1.0` release image produced by GitHub Actions.

The API is available at these routes:

- `GET /health`
- `GET /notes`
- `POST /notes`
- `GET /notes/{id}`
- `DELETE /notes/{id}`
- `GET /metrics`

I pull the immutable release tag instead of rebuilding the application in the Space. This keeps the artifact tested by the release workflow identical to the artifact deployed by Hugging Face.
