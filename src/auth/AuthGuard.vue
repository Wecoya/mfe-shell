<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getKeycloak } from './keycloak'

const router = useRouter()
const isAuthenticated = ref(false)
const isLoading = ref(true)

onMounted(() => {
  try {
    const kc = getKeycloak()
    isAuthenticated.value = kc.authenticated ?? false
  } catch {
    isAuthenticated.value = false
  }

  if (!isAuthenticated.value) {
    const kc = getKeycloak()
    kc.login({ redirectUri: window.location.origin + router.currentRoute.value.fullPath })
  }

  isLoading.value = false
})
</script>

<template>
  <div v-if="isLoading" class="auth-loading">
    <p>Authenticating...</p>
  </div>
  <slot v-else-if="isAuthenticated" />
  <div v-else class="auth-redirect">
    <p>Redirecting to login...</p>
  </div>
</template>

<style scoped>
.auth-loading,
.auth-redirect {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  font-family: system-ui, sans-serif;
}
</style>
