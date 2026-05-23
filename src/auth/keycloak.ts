import Keycloak from 'keycloak-js'
import type { KeycloakConfig } from 'keycloak-js'

let keycloakInstance: Keycloak | null = null
let refreshInterval: ReturnType<typeof setInterval> | null = null

export interface AppConfig {
  remotes: Record<string, string>
  keycloak: {
    url: string
    realm: string
    clientId: string
  }
}

async function loadConfig(): Promise<AppConfig> {
  const response = await fetch('/config.json')
  if (!response.ok) {
    throw new Error(`Failed to load config: ${response.status}`)
  }
  return response.json()
}

export async function initKeycloak(): Promise<Keycloak> {
  if (keycloakInstance) return keycloakInstance

  const config = await loadConfig()

  const kcConfig: KeycloakConfig = {
    url: config.keycloak.url,
    realm: config.keycloak.realm,
    clientId: config.keycloak.clientId,
  }

  keycloakInstance = new Keycloak(kcConfig)

  const authenticated = await keycloakInstance.init({
    onLoad: 'login-required',
    pkceMethod: 'S256',
    checkLoginIframe: false,
    silentCheckSsoRedirectUri: undefined,
  })

  if (!authenticated) {
    throw new Error('Authentication failed')
  }

  startTokenRefresh(keycloakInstance)

  return keycloakInstance
}

function startTokenRefresh(kc: Keycloak): void {
  if (refreshInterval) {
    clearInterval(refreshInterval)
  }

  refreshInterval = setInterval(async () => {
    try {
      const refreshed = await kc.updateToken(60)
      if (refreshed) {
        console.debug('[auth] Token refreshed')
      }
    } catch {
      console.warn('[auth] Token refresh failed, redirecting to login')
      kc.login()
    }
  }, 30_000)
}

export function getKeycloak(): Keycloak {
  if (!keycloakInstance) {
    throw new Error('Keycloak not initialized. Call initKeycloak() first.')
  }
  return keycloakInstance
}

export function logout(): void {
  if (refreshInterval) {
    clearInterval(refreshInterval)
    refreshInterval = null
  }
  keycloakInstance?.logout({ redirectUri: window.location.origin })
}
