<script setup lang="ts">
import { computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useUserStore } from '@/store/user'
import { logout } from '@/auth/keycloak'
import type { RemoteEntry } from '@/federation/remote-config'

defineProps<{
  remotes: RemoteEntry[]
}>()

const router = useRouter()
const route = useRoute()
const userStore = useUserStore()

const currentPath = computed(() => route.path)

function navigate(path: string): void {
  router.push(path)
}

function handleLogout(): void {
  userStore.clear()
  logout()
}
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar">
      <div class="sidebar-header">
        <h1 class="logo">Wecoya</h1>
      </div>
      <nav class="nav-menu">
        <button
          v-for="remote in remotes"
          :key="remote.name"
          class="nav-item"
          :class="{ active: currentPath.startsWith(remote.route) }"
          @click="navigate(remote.route)"
        >
          {{ remote.label }}
        </button>
      </nav>
    </aside>

    <div class="main-area">
      <header class="top-bar">
        <div class="breadcrumb">
          <span>{{ route.meta.title || 'Dashboard' }}</span>
        </div>
        <div class="user-info">
          <span class="user-name">{{ userStore.displayName }}</span>
          <button class="logout-btn" @click="handleLogout">Logout</button>
        </div>
      </header>

      <main class="content">
        <slot />
      </main>
    </div>
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  height: 100vh;
  font-family: system-ui, -apple-system, sans-serif;
}

.sidebar {
  width: 240px;
  background: #1a1a2e;
  color: #fff;
  display: flex;
  flex-direction: column;
}

.sidebar-header {
  padding: 1.5rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

.logo {
  font-size: 1.5rem;
  font-weight: 700;
  margin: 0;
}

.nav-menu {
  padding: 1rem 0;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.nav-item {
  display: block;
  width: 100%;
  padding: 0.75rem 1.5rem;
  background: none;
  border: none;
  color: rgba(255, 255, 255, 0.7);
  text-align: left;
  cursor: pointer;
  font-size: 0.95rem;
  transition: background 0.2s, color 0.2s;
}

.nav-item:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #fff;
}

.nav-item.active {
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
  border-left: 3px solid #4f8cff;
}

.main-area {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1.5rem;
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.user-name {
  font-size: 0.9rem;
  color: #374151;
}

.logout-btn {
  padding: 0.4rem 0.8rem;
  background: #ef4444;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.85rem;
}

.logout-btn:hover {
  background: #dc2626;
}

.content {
  flex: 1;
  padding: 1.5rem;
  overflow-y: auto;
  background: #f9fafb;
}
</style>
