# Lab 10 teardown

## Hugging Face Space

After collecting the required evidence, I can remove the deployment from the Space settings by selecting **Delete this Space** and confirming its name. Leaving the free CPU Space sleeping is also acceptable and does not incur a charge.

## GitHub Container Registry

The public `v0.1.0` image is release evidence, so I leave it available for assessment. If removal is required later, I can open my GitHub profile, select **Packages**, open `devops-intro/quicknotes`, and delete the package version from its settings.

## Local state

I can stop and remove any local test container without affecting either hosted artifact:

```bash
docker rm -f quicknotes-lab10
```
