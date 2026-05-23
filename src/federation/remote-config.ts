export interface RemoteEntry {
  name: string
  url: string
  label: string
  route: string
  icon?: string
}

export interface RuntimeConfig {
  remotes: Record<string, string>
  keycloak: {
    url: string
    realm: string
    clientId: string
  }
}

let cachedConfig: RuntimeConfig | null = null

export async function fetchRuntimeConfig(retries = 3, delayMs = 5000): Promise<RuntimeConfig> {
  if (cachedConfig) return cachedConfig

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const response = await fetch('/config.json')
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
      cachedConfig = await response.json()
      return cachedConfig!
    } catch (error) {
      console.warn(`[federation] Config fetch attempt ${attempt}/${retries} failed:`, error)
      if (attempt < retries) {
        await new Promise((resolve) => setTimeout(resolve, delayMs))
      }
    }
  }

  throw new Error('Failed to load runtime configuration after all retries')
}

export function parseRemoteEntries(config: RuntimeConfig): RemoteEntry[] {
  return Object.entries(config.remotes).map(([name, url]) => ({
    name,
    url,
    label: name.charAt(0).toUpperCase() + name.slice(1),
    route: `/${name}`,
  }))
}

export function getRuntimeConfig(): RuntimeConfig | null {
  return cachedConfig
}
