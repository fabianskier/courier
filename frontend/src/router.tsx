import { QueryClient } from '@tanstack/react-query'
import { createRouter, type RouterHistory } from '@tanstack/react-router'
import { routeTree } from './routeTree.gen'

export interface RouterContext {
  queryClient: QueryClient
}

// One function for the app and the tests: tests pass a memory history and a
// fresh QueryClient, so every test starts from a clean cache.
export function createAppRouter(queryClient: QueryClient, history?: RouterHistory) {
  return createRouter({
    routeTree,
    context: { queryClient },
    history,
    defaultPreload: 'intent',
    // Loaders read from TanStack Query's cache, which decides freshness.
    defaultPreloadStaleTime: 0,
    scrollRestoration: true,
  })
}

export function createAppQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: { staleTime: 5_000, retry: 1 },
    },
  })
}

declare module '@tanstack/react-router' {
  interface Register {
    router: ReturnType<typeof createAppRouter>
  }
}
