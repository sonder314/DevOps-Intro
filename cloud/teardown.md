# Lab 10 teardown

## Render service

After collecting the required evidence, I can suspend or delete the web service from its Render settings. I also remove the `RENDER_DEPLOY_HOOK_URL` GitHub Actions secret if the service is deleted.

## GitHub Container Registry

The public `v0.1.0` image is release evidence, so I leave it available for assessment. If removal is required later, I can open my GitHub profile, select **Packages**, open `devops-intro/quicknotes`, and delete the package version from its settings.

## Local state

I can stop and remove any local test container without affecting the hosted artifact:

```bash
docker rm -f quicknotes-lab10
```
