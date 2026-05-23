import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { getKeycloak } from '@/auth/keycloak'

export interface UserProfile {
  sub: string
  email: string
  name: string
  preferredUsername: string
  realmRoles: string[]
  resourceAccess: Record<string, { roles: string[] }>
  tenant?: string
}

export const useUserStore = defineStore('user', () => {
  const profile = ref<UserProfile | null>(null)
  const isLoaded = ref(false)

  const isAuthenticated = computed(() => profile.value !== null)
  const displayName = computed(() => profile.value?.name ?? profile.value?.preferredUsername ?? 'Unknown')
  const email = computed(() => profile.value?.email ?? '')
  const roles = computed(() => profile.value?.realmRoles ?? [])
  const tenant = computed(() => profile.value?.tenant ?? 'default')

  function loadFromKeycloak(): void {
    const kc = getKeycloak()
    if (!kc.authenticated || !kc.tokenParsed) {
      profile.value = null
      isLoaded.value = true
      return
    }

    const parsed = kc.tokenParsed
    profile.value = {
      sub: parsed.sub ?? '',
      email: parsed.email ?? '',
      name: parsed.name ?? '',
      preferredUsername: parsed.preferred_username ?? '',
      realmRoles: parsed.realm_access?.roles ?? [],
      resourceAccess: parsed.resource_access ?? {},
      tenant: parsed.tenant as string | undefined,
    }
    isLoaded.value = true
  }

  function clear(): void {
    profile.value = null
    isLoaded.value = false
  }

  return {
    profile,
    isLoaded,
    isAuthenticated,
    displayName,
    email,
    roles,
    tenant,
    loadFromKeycloak,
    clear,
  }
})
