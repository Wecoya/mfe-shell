# MFE Shell — Wecoya Platform

Micro-Frontend Shell Application for the Wecoya platform. Hosts domain-specific
Vue.js MFEs (Claims, Fleet, Finance) via Vite Module Federation with Keycloak
OIDC authentication.

## Architecture

- **Framework**: Vue 3 + TypeScript + Vite
- **Module Federation**: `@originjs/vite-plugin-federation` (host mode)
- **Auth**: Keycloak OIDC (PKCE flow via `keycloak-js`)
- **Deployment**: nginx:alpine container on Kubernetes (App Cluster)
- **GitOps**: ArgoCD syncs from `k8s/overlays/<env>`

## Development

```bash
npm install
npm run dev        # Dev server at http://localhost:3000
npm run build      # Production build
npm run test       # Run tests
npm run lint       # Lint code
npm run typecheck  # TypeScript check
```

## Docker

```bash
docker build -t mfe-shell:local .
docker run -p 8080:8080 \
  -e MFE_REMOTES='{"claims":"http://localhost:3001/remoteEntry.js"}' \
  -e KEYCLOAK_URL="http://localhost:8180" \
  mfe-shell:local
```

## K8s Validation

```bash
kustomize build k8s/overlays/dev | kubeconform -strict -kubernetes-version 1.29.0
```

## Configuration

Remote MFE URLs and Keycloak settings are injected at container startup via
environment variables (sourced from Kubernetes ConfigMap):

| Variable | Description | Default |
|----------|-------------|---------|
| `MFE_REMOTES` | JSON object of remote name→URL | `{}` |
| `KEYCLOAK_URL` | Keycloak base URL | `https://auth.wecoya.de` |
| `KEYCLOAK_REALM` | Keycloak realm name | `wecoya` |
| `KEYCLOAK_CLIENT_ID` | OIDC client ID | `mfe-shell` |
