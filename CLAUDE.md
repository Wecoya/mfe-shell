# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A service repo generated from the Wecoya `vue-mfe` Copier template and deployed to the
Private Sovereign Cloud (PSC). It contains a Vue 3 micro-frontend (MFE), CI workflows, and a
GitOps-compatible `k8s/` directory that ArgoCD on the management cluster watches.

## Non-negotiable rules

- **No plaintext secrets** — use External Secrets Operator (ESO) pulling from Vault.
- **No `:latest` image tags** in `k8s/` manifests.
- **GitOps only** — commit changes to Git; never `kubectl apply` directly in production.
- **All content (code, comments, commit messages) must be in English.** Only user-facing UI may be in another language.

## Validation before PR

```bash
npm run lint && npm run test && npm run build
```

## Task Quality Gates

### Definition of Ready (confirm before starting a task)

- Target repository is unambiguous
- Acceptance criteria / observable outcome defined
- No unresolved blocking dependencies

### Definition of Done

- PR merged to main in this repository
- All CI checks pass (lint, test, build)
- If this repo is a PSC submodule: submodule pointer advanced in Wecoya/private-sovereign-cloud
- [Optional] Dev-deploy green — verify via `argocd app get <app-name>` on the mgmt cluster or a live health endpoint
