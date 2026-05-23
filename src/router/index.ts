import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import type { RemoteEntry } from '@/federation/remote-config'
import RemoteLoader from '@/layout/RemoteLoader.vue'

const staticRoutes: RouteRecordRaw[] = [
  {
    path: '/',
    redirect: '/dashboard',
  },
  {
    path: '/dashboard',
    name: 'dashboard',
    component: () => import('@/views/Dashboard.vue'),
    meta: { title: 'Dashboard' },
  },
]

export function createAppRouter(remotes: RemoteEntry[]) {
  const remoteRoutes: RouteRecordRaw[] = remotes.map((remote) => ({
    path: `${remote.route}/:pathMatch(.*)*`,
    name: remote.name,
    component: RemoteLoader,
    props: {
      remoteName: remote.name,
      remoteUrl: remote.url,
    },
    meta: { title: remote.label },
  }))

  const router = createRouter({
    history: createWebHistory(),
    routes: [...staticRoutes, ...remoteRoutes],
  })

  return router
}
