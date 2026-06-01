# Wecoya Vue MFE Template

Reference platform template for Vue microfrontends.

## CI/CD Workflows

| Workflow | Trigger | Effect |
|---|---|---|
| `main.yml` | Push to `main` | Build, scan, publish image, and update dev deployment |
| `pr.yml` | Pull request to `main` | Quality + security gate before merge |
| `promote.yml` | Manual `workflow_dispatch` | Promote a known image SHA to staging or prod |

### Promoting to Staging / Production

```bash
# 1. Find the SHA of the build you want to promote
gh run list --workflow=main.yml --limit 5

# 2. Get the full 7-char image SHA (format: sha-XXXXXXX)
gh run view <run-id> --log | grep "image_sha"

# 3. Trigger promotion
gh workflow run promote.yml \
  --field image_sha=sha-XXXXXXX \
  --field environment=staging   # or: production
```

Image tags always follow the format `sha-XXXXXXX` where `XXXXXXX` is the first 7 characters of the Git commit SHA.

## Ownership Contract

This template follows a strict three-layer ownership model:

1. Layer 1 (scaffold-only app code): `src/**`, app-specific `package.json`, and frontend feature code remain repository-owned.
2. Layer 2 (template-managed platform surface): `.github/workflows/main.yml`, `.github/workflows/pr.yml`, `.github/workflows/promote.yml`, `k8s/**`, `Dockerfile`, `nginx.conf`, and `catalog-info.yaml` are kept in sync from this template. Updates are delivered by the `template-sync.yml` workflow in `private-sovereign-cloud` via `MFE_NAME` placeholder substitution (`scripts/rename.sh`), **not** Copier variable expansion — `k8s/` files use the literal placeholder `MFE_NAME` which `rename.sh` replaces with the actual repo name during scaffolding.
3. Layer 3 (scaffold-only lifecycle): one-time bootstrap and security setup workflows such as `.github/workflows/bootstrap-repo.yml` and `.github/workflows/codeql.yml` stay in Backstage skeletons and are not synchronized by `template-sync.yml`.
