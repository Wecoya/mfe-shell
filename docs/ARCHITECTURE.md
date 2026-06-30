# Architecture — mfe-shell

## Bounded Context

**Context**: _Describe the DDD bounded context this MFE belongs to._
**Responsibilities**: _Describe which UI features this MFE exposes._

## Runtime

Deployed as a **static file server (Nginx)** on the `app` cluster via the `WecoyaMfeInfra` XR claim.
The MFE uses **Vite Module Federation** (`@originjs/vite-plugin-federation`) to expose Vue 3 components
to a shell application at runtime without shared bundling.

## Module Federation

| Attribute | Value |
|---|---|
| Module name | `mfe-shell` |
| Exposed components | _List the Vue components exposed via Module Federation_ |
| Remote entry | `/remoteEntry.js` |

## Key Dependencies

| Dependency | Purpose |
|---|---|
| Nginx | Static file serving and module entry point |
| Vue 3 | UI framework |
| Vite + federation plugin | Build tooling and module federation |

## Infrastructure Claim

The MFE's infrastructure (Nginx Deployment, IngressRoute, ExternalSecrets) is managed
by the `WecoyaMfeInfra` XR claim at:
`infra/base/crossplane/claims/mfe-shell.yaml`

## Deployment Model

| Environment | ArgoCD App | Namespace |
|---|---|---|
| dev | `mfe-shell-dev` | `mfe-shell-dev` |
| staging | `mfe-shell-staging` | `mfe-shell-staging` |
| prod | `mfe-shell-prod` | `mfe-shell-prod` |

## Observability

| Signal | Tool | Reference |
|---|---|---|
| Metrics | Prometheus / Grafana | `svc-mfe-shell` dashboard |
| Logs | Loki | label `service=mfe-shell` |

ServiceMonitor is deployed per environment (e.g. `mfe-shell-dev`, `mfe-shell-prod`).
Nginx access logs are forwarded to Loki via the platform log collector on the `app` cluster.
