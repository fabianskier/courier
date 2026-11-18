import { type QueryClient, queryOptions, useSuspenseQuery } from '@tanstack/react-query'
import { redirect } from '@tanstack/react-router'
import { ApiError, apiFetch, onUnauthorized } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import { stopLive } from '@/lib/live/connection'
import type { Me } from '@/lib/api/types'
import { clearKey } from '@/lib/session'
import type { AppRouter } from '@/router'

// The key in use: name and scopes. Cached until sign-out clears the cache.
export function meQueryOptions() {
  return queryOptions({
    queryKey: queryKeys.me,
    queryFn: ({ signal }) => apiFetch<Me>('/me', { signal }),
    staleTime: Infinity,
  })
}

// Loads `/me` for the stored key before a signed-in page renders; a key it
// rejects sends the operator to sign in, coming back to `href`.
export async function ensureMe(queryClient: QueryClient, href: string) {
  await queryClient.ensureQueryData(meQueryOptions()).catch((error: unknown) => {
    if (!(error instanceof ApiError) || error.status !== 401) throw error
    throw redirect({ to: '/sign-in', search: { redirect: href, reason: 'expired' } })
  })
}

// Inside the shell only (`_app` and the signed-in overview): their guards have
// already loaded `/me`.
export function useMe() {
  return useSuspenseQuery(meQueryOptions()).data
}

// Whether the key in use may change merchants and endpoints.
export const useCanWrite = () => useMe().scopes.includes('write')

// Only same-app paths are followed after sign-in, never another origin.
export const safeRedirect = (value = '') => (/^\/(?![/\\]|sign-in)/.test(value) ? value : '/')

// The dashboard socket closes first. The cache is cleared once the data pages
// are gone, so none of them refetches.
export async function signOut(router: AppRouter, queryClient: QueryClient) {
  stopLive()
  clearKey()
  await router.navigate({ to: '/sign-in' })
  queryClient.clear()
}

// A `401` for the stored key: forget it and its data, and ask for a new one,
// coming back to the page the operator was on.
export function installUnauthorizedHandler(router: AppRouter, queryClient: QueryClient) {
  return onUnauthorized(async () => {
    stopLive()
    clearKey()
    const { href, pathname } = router.latestLocation
    if (pathname !== '/sign-in') {
      await router.navigate({ to: '/sign-in', search: { reason: 'expired', redirect: href } })
    }
    queryClient.clear()
  })
}
