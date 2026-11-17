import { infiniteQueryOptions, queryOptions } from '@tanstack/react-query'
import { z } from 'zod'
import { apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import type { EndpointDetail, Page } from '@/lib/api/types'

// The endpoints list's URL search: unknown or invalid values are dropped.
// "Degraded only" is kept as `degraded=true`; off is no parameter at all.
export const endpointFiltersSchema = z.object({
  merchant_id: z.string().min(1).optional().catch(undefined),
  degraded: z.literal(true).optional().catch(undefined),
})

export type EndpointFilters = z.infer<typeof endpointFiltersSchema>

// Newest first; each page follows the previous page's `next_cursor`.
export function endpointsQueryOptions(filters: EndpointFilters) {
  return infiniteQueryOptions({
    queryKey: queryKeys.endpointList(filters),
    queryFn: ({ pageParam, signal }) =>
      apiFetch<Page<EndpointDetail>>('/endpoints', {
        query: {
          merchant_id: filters.merchant_id,
          degraded: filters.degraded ? 'true' : undefined,
          cursor: pageParam,
        },
        signal,
      }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (page) => page.next_cursor ?? undefined,
  })
}

export function endpointQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.endpoint(id),
    queryFn: ({ signal }) =>
      apiFetch<{ data: EndpointDetail }>(`/endpoints/${encodeURIComponent(id)}`, { signal }),
    select: (body) => body.data,
  })
}
