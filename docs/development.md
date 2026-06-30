# Development — mfe-shell

## Prerequisites

- Node.js >= 20 (via `nvm use`)
- Docker + Docker Compose (for running the shell app alongside this MFE)

## Local Setup

```bash
# 1. Clone the repository
git clone https://github.com/Wecoya/mfe-shell.git
cd mfe-shell

# 2. Install dependencies
npm install

# 3. Start the Vite dev server
npm run dev
```

The MFE dev server is available at `http://localhost:5173`.
The remote entry point for Module Federation is at `http://localhost:5173/remoteEntry.js`.

To run with the full shell application and other MFEs, start the `mfe-shell` repo's
dev environment (see the `mfe-shell` repository README for instructions).

## Running Tests

```bash
# Unit tests (Vitest)
npm run test

# Watch mode for TDD
npm run test:watch

# Coverage report
npm run test:coverage
```

## Linting and Formatting

```bash
# ESLint
npm run lint

# Prettier check
npm run format:check

# Prettier fix
npm run format
```

## Debugging

- **Vue DevTools**: Install the Vue DevTools browser extension; the Vite dev server enables it automatically.
- **Module Federation**: If a remote module fails to load, check that `remoteEntry.js` is accessible and that the shell app's `remote` configuration points to the correct URL.
- **Nginx (production)**: Check the Nginx container logs via Loki with label `service=mfe-shell`.

## Build and Static Preview

```bash
# Production build
npm run build

# Preview the production build locally via a static server
npm run preview
```

The `dist/` folder contains the built static assets including `remoteEntry.js` for Module Federation.

## Useful Scripts

| Script | Purpose |
|---|---|
| `npm run dev` | Start Vite dev server with hot reload |
| `npm run build` | Production build (outputs to `dist/`) |
| `npm run preview` | Serve the `dist/` folder locally |
| `npm run test` | Run Vitest unit tests |
| `npm run lint` | Run ESLint |
