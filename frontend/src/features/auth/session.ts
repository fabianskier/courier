import { type QueryClient, queryOptions, useSuspenseQuery } from '@tanstack/react-query'
import { apiFetch, onUnauthorized } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
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

// Inside `_app` only: its guard has already loaded `/me`.
export function useMe() {
  return useSuspenseQuery(meQueryOptions()).data
}

// Only same-app paths are followed after sign-in, never another origin.
export function safeRedirect(value: string | undefined): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) {
    return '/'
  }
  if (value === '/sign-in' || value.startsWith('/sign-in?')) return '/'
  return value
}

// The cache is cleared once the data pages are gone, so none of them refetches.
export async function signOut(router: AppRouter, queryClient: QueryClient) {
  clearKey()
  await router.navigate({ to: '/sign-in' })
  queryClient.clear()
}

// A `401` for the stored key: forget it and its data, and ask for a new one,
// coming back to the page the operator was on.
export function installUnauthorizedHandler(router: AppRouter, queryClient: QueryClient) {
  return onUnauthorized(async () => {
    clearKey()
    const { href, pathname } = router.latestLocation
    if (pathname !== '/sign-in') {
      await router.navigate({ to: '/sign-in', search: { reason: 'expired', redirect: href } })
    }
    queryClient.clear()
  })
}
