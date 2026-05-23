<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { createPinia } from 'pinia'
import AppShell from '@/layout/AppShell.vue'
import { useUserStore } from '@/store/user'
import { fetchRuntimeConfig, parseRemoteEntries, type RemoteEntry } from '@/federation/remote-config'

const remotes = ref<RemoteEntry[]>([])
const isReady = ref(false)
const configError = ref('')

onMounted(async () => {
  try {
    const config = await fetchRuntimeConfig()
    remotes.value = parseRemoteEntries(config)
    const userStore = useUserStore()
    userStore.loadFromKeycloak()
    isReady.value = true
  } catch (error) {
    configError.value = error instanceof Error ? error.message : 'Configuration unavailable'
  }
})
</script>

<template>
  <div v-if="configError" class="config-error">
    <h2>Configuration unavailable</h2>
    <p>{{ configError }}</p>
    <button @click="() => window.location.reload()">Retry</button>
  </div>
  <AppShell v-else-if="isReady" :remotes="remotes">
    <router-view />
  </AppShell>
  <div v-else class="app-loading">
    <p>Loading platform...</p>
  </div>
</template>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

.config-error {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100vh;
  gap: 1rem;
  font-family: system-ui, sans-serif;
}

.app-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  font-family: system-ui, sans-serif;
}
</style>
