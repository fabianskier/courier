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

// The forms' event-type filters input:
// "payment.*, refund.created" -> ["payment.*", "refund.created"].
export const splitEventTypes = (value: string) =>
  value
    .split(',')
    .map((type) => type.trim())
    .filter(Boolean)

// What `POST /api/v1/endpoints` accepts; the API fills in what is left out.
export type NewEndpoint = {
  merchant_id: string
  url: string
  description?: string
  event_types: string[]
  retry_window_seconds: number
  retry_on_4xx: boolean
  max_concurrency: number
}

// Creates an endpoint and splits off its signing secret: callers keep the
// secret in component state only, never in a query or mutation result.
export async function createEndpoint(body: NewEndpoint) {
  const { data } = await apiFetch<{ data: EndpointDetail & { secret: string } }>('/endpoints', {
    method: 'POST',
    body,
  })
  const { secret, ...endpoint } = data
  return { endpoint, secret }
}

export function endpointQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.endpoint(id),
    queryFn: ({ signal }) =>
      apiFetch<{ data: EndpointDetail }>(`/endpoints/${encodeURIComponent(id)}`, { signal }),
    select: (body) => body.data,
  })
}
