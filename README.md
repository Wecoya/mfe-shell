# Wecoya Vue MFE Template

Reference platform template for Vue microfrontends.

## CI/CD Workflows

| Workflow | Trigger | Effect |
|---|---|---|
| `main.yml` | Push to `main` | Build, scan, publish image, and update dev deployment |
| `pr.yml` | Pull request to `main` | Quality + security gate before merge |
| `promote.yml` | Manual `workflow_dispatch` | Promote a known image SHA to staging or prod |

## Ownership Contract

This template follows a strict three-layer ownership model:

1. Layer 1 (scaffold-only app code): `src/**`, app-specific `package.json`, and frontend feature code remain repository-owned.
2. Layer 2 (Copier-managed platform surface): `.github/workflows/main.yml`, `.github/workflows/pr.yml`, `.github/workflows/promote.yml`, `k8s/**`, `Dockerfile`, `nginx.conf`, and `catalog-info.yaml` are synchronized from this template.
3. Layer 3 (scaffold-only lifecycle): one-time bootstrap and security setup workflows such as `.github/workflows/bootstrap-repo.yml` and `.github/workflows/codeql.yml` stay in Backstage skeletons and are not managed by Copier.
