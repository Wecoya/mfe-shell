<script setup lang="ts">
import { ref, onMounted, onUnmounted, shallowRef, type Component } from 'vue'

const props = defineProps<{
  remoteName: string
  remoteUrl: string
}>()

const isLoading = ref(true)
const hasError = ref(false)
const errorMessage = ref('')
const RemoteComponent = shallowRef<Component | null>(null)
const injectedScripts: HTMLScriptElement[] = []

onMounted(async () => {
  try {
    const module = await loadRemoteModule(props.remoteName, props.remoteUrl)
    RemoteComponent.value = module.default || module
    isLoading.value = false
  } catch (error) {
    hasError.value = true
    errorMessage.value = error instanceof Error ? error.message : 'Unknown error loading module'
    isLoading.value = false
    console.error(`[RemoteLoader] Failed to load ${props.remoteName}:`, error)
  }
})

onUnmounted(() => {
  for (const script of injectedScripts) {
    script.parentNode?.removeChild(script)
  }
  injectedScripts.length = 0
})

async function loadRemoteModule(_name: string, url: string): Promise<{ default: Component }> {
  const container = await loadRemoteEntry(url)
  const factory = await container.get('./App')
  return factory()
}

async function loadRemoteEntry(url: string): Promise<{ get: (module: string) => Promise<() => { default: Component }> }> {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = url
    script.type = 'text/javascript'
    script.async = true

    script.onload = () => {
      injectedScripts.push(script)
      const name = url.split('/').pop()?.replace('.js', '') ?? ''
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const container = (window as any)[name]
      if (container) {
        container.init({
          vue: () => Promise.resolve(() => import('vue')),
          pinia: () => Promise.resolve(() => import('pinia')),
        })
        resolve(container)
      } else {
        reject(new Error(`Remote container "${name}" not found on window`))
      }
    }

    script.onerror = () => {
      reject(new Error(`Failed to load remote entry: ${url}`))
      document.head.removeChild(script)
    }

    document.head.appendChild(script)
  })
}

function retry(): void {
  // Remove previously injected scripts before retrying
  for (const script of injectedScripts) {
    script.parentNode?.removeChild(script)
  }
  injectedScripts.length = 0

  hasError.value = false
  isLoading.value = true
  errorMessage.value = ''

  loadRemoteModule(props.remoteName, props.remoteUrl)
    .then((module) => {
      RemoteComponent.value = module.default || module
      isLoading.value = false
    })
    .catch((error) => {
      hasError.value = true
      errorMessage.value = error instanceof Error ? error.message : 'Unknown error'
      isLoading.value = false
    })
}
</script>

<template>
  <div class="remote-loader">
    <div v-if="isLoading" class="loading-state">
      <div class="spinner"></div>
      <p>Loading {{ remoteName }}...</p>
    </div>

    <div v-else-if="hasError" class="error-state">
      <div class="error-icon">⚠️</div>
      <h3>Module unavailable</h3>
      <p>{{ errorMessage }}</p>
      <button class="retry-btn" @click="retry">Try again</button>
    </div>

    <component v-else-if="RemoteComponent" :is="RemoteComponent" />
  </div>
</template>

<style scoped>
.remote-loader {
  width: 100%;
  height: 100%;
}

.loading-state,
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 3rem;
  text-align: center;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 3px solid #e5e7eb;
  border-top-color: #4f8cff;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.error-icon {
  font-size: 3rem;
  margin-bottom: 1rem;
}

.error-state h3 {
  margin: 0 0 0.5rem;
  color: #374151;
}

.error-state p {
  color: #6b7280;
  margin-bottom: 1.5rem;
}

.retry-btn {
  padding: 0.5rem 1.5rem;
  background: #4f8cff;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.9rem;
}

.retry-btn:hover {
  background: #3b7ae0;
}
</style>
