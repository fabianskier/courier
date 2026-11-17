import { QueryClientProvider } from '@tanstack/react-query'
import { createMemoryHistory, RouterProvider } from '@tanstack/react-router'
import { render } from '@testing-library/react'
import { createAppQueryClient, createAppRouter } from '@/router'

// Renders the whole app at `path`, with a fresh cache and in-memory history.
export function renderApp(path = '/') {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({ queries: { retry: false } })
  const history = createMemoryHistory({ initialEntries: [path] })
  const router = createAppRouter(queryClient, history)

  const result = render(
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  )

  return { ...result, router, queryClient }
}
