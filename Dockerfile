# syntax=docker/dockerfile:1
# Multi-stage build: node builder → nginx static server
#
# Stage 1: Build Vue app
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --frozen-lockfile
COPY . .
RUN npm run build

# Stage 2: Serve with nginx (non-root, read-only rootfs compatible)
FROM nginx:1.27-alpine AS runner

# Create non-root user/group (UID 1001) that nginx worker processes run as
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copy built assets
COPY --from=builder /app/dist /usr/share/nginx/html

# Custom nginx config — SPA routing + proper cache headers for remoteEntry.js
COPY nginx.conf /etc/nginx/conf.d/default.conf

# nginx master process needs to bind port 8080 (non-root), adjust log dirs
RUN chown -R appuser:appgroup /var/cache/nginx /var/log/nginx /var/run /etc/nginx/conf.d

USER 1001

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s CMD \
  wget -qO- http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
