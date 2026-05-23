import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { initKeycloak } from '@/auth/keycloak'
import { fetchRuntimeConfig, parseRemoteEntries } from '@/federation/remote-config'
import { createAppRouter } from '@/router'

async function bootstrap(): Promise<void> {
  try {
    // 1. Load runtime config (remote URLs, keycloak config)
    const config = await fetchRuntimeConfig()
    const remotes = parseRemoteEntries(config)

    // 2. Initialize Keycloak (redirects to login if not authenticated)
    await initKeycloak()

    // 3. Create Vue app with plugins
    const app = createApp(App)
    const pinia = createPinia()
    const router = createAppRouter(remotes)

    app.use(pinia)
    app.use(router)

    // 4. Mount
    app.mount('#app')
  } catch (error) {
    console.error('[mfe-shell] Bootstrap failed:', error)
    document.getElementById('app')!.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:center;height:100vh;font-family:system-ui">
        <div style="text-align:center">
          <h2>Platform Error</h2>
          <p>${error instanceof Error ? error.message : 'Unknown error'}</p>
          <button onclick="window.location.reload()" style="margin-top:1rem;padding:0.5rem 1rem">Retry</button>
        </div>
      </div>
    `
  }
}

bootstrap()
