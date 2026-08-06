# mfe-shell

[![CI](https://github.com/Wecoya/mfe-shell/actions/workflows/main.yml/badge.svg)](https://github.com/Wecoya/mfe-shell/actions/workflows/main.yml)
[![Backstage](https://img.shields.io/badge/Backstage-catalog-blue)](https://backstage.plattform.wecoya.online/catalog/default/component/mfe-shell)

A **Vue 3 Microfrontend** (Module Federation) in the Wecoya platform, served via Nginx.

## Quick Start

```bash
# Install dependencies
npm install

# Start the Vite dev server (exposes the module at http://localhost:5173)
npm run dev
```

To run together with the shell app and other MFEs, start the `mfe-shell` repo's
dev environment (see the `mfe-shell` repository README for instructions).

## Service Table

| Service | URL |
|---|---|
| MFE Dev Server | `http://localhost:5173` |
| Backstage Catalog | [mfe-shell](https://backstage.plattform.wecoya.online/catalog/default/component/mfe-shell) |
| ArgoCD | [mfe-shell-dev](https://gitops.plattform.wecoya.online/applications/mfe-shell-dev) |
| Grafana | [CI Health](https://monitoring.plattform.wecoya.online/d/platform-ci-health/platform-ci-health?var-repo=Wecoya/mfe-shell) |
| GitHub | [Wecoya/mfe-shell](https://github.com/Wecoya/mfe-shell) |

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `VITE_API_BASE_URL` | Base URL for backend API calls | `http://localhost:3000` |
| `VITE_KEYCLOAK_URL` | Keycloak auth endpoint | `http://localhost:8080` |

Copy `.env.example` to `.env` and adjust values before starting.

## Links

- [Backstage Catalog](https://backstage.plattform.wecoya.online/catalog/default/component/mfe-shell)
- [TechDocs](https://backstage.plattform.wecoya.online/docs/default/component/mfe-shell)
- [ArgoCD (dev)](https://gitops.plattform.wecoya.online/applications/mfe-shell-dev)
- [Grafana Dashboard](https://monitoring.plattform.wecoya.online/d/svc-mfe-shell/service-overview)
