#!/bin/sh
set -e

# Generate config.json from environment variables
# MFE_REMOTES is a JSON object of remote names to URLs
# e.g. MFE_REMOTES='{"claims":"https://claims.wecoya.de/remoteEntry.js"}'

CONFIG_FILE="/usr/share/nginx/html/config.json"

if [ -n "$MFE_REMOTES" ]; then
  cat > "$CONFIG_FILE" <<EOF
{
  "remotes": $MFE_REMOTES,
  "keycloak": {
    "url": "${KEYCLOAK_URL:-https://auth.wecoya.de}",
    "realm": "${KEYCLOAK_REALM:-wecoya}",
    "clientId": "${KEYCLOAK_CLIENT_ID:-mfe-shell}"
  }
}
EOF
elif [ -f "/config/remotes.json" ]; then
  # Fallback: read from mounted ConfigMap volume
  REMOTES=$(cat /config/remotes.json)
  cat > "$CONFIG_FILE" <<EOF
{
  "remotes": $REMOTES,
  "keycloak": {
    "url": "${KEYCLOAK_URL:-https://auth.wecoya.de}",
    "realm": "${KEYCLOAK_REALM:-wecoya}",
    "clientId": "${KEYCLOAK_CLIENT_ID:-mfe-shell}"
  }
}
EOF
else
  echo '{"remotes":{},"keycloak":{"url":"https://auth.wecoya.de","realm":"wecoya","clientId":"mfe-shell"}}' > "$CONFIG_FILE"
fi

exec "$@"
