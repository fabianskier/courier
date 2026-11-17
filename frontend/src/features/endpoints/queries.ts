import { infiniteQueryOptions, queryOptions, useQueryClient } from '@tanstack/react-query'
import { z } from 'zod'
import { ApiError, apiFetch } from '@/lib/api/client'
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

const endpointPath = (id: string) => `/endpoints/${encodeURIComponent(id)}`

// What `PATCH /api/v1/endpoints/:id` accepts; only changed fields are sent.
export type EndpointChanges = Partial<Omit<NewEndpoint, 'merchant_id'>> & { enabled?: boolean }

export const updateEndpoint = (id: string, changes: EndpointChanges) =>
  apiFetch<{ data: EndpointDetail }>(endpointPath(id), { method: 'PATCH', body: changes })

// Rotates the signing secret and splits it off, like `createEndpoint`.
export async function rotateEndpointSecret(id: string) {
  const { data } = await apiFetch<{ data: EndpointDetail & { secret: string } }>(
    `${endpointPath(id)}/rotate_secret`,
    { method: 'POST' },
  )
  const { secret, ...endpoint } = data
  return { endpoint, secret }
}

// After a change: the updated endpoint is shown at once, and every endpoint
// list and lookup is refetched so URLs and states stay current.
export function useEndpointSaved() {
  const queryClient = useQueryClient()
  return async (endpoint: EndpointDetail) => {
    queryClient.setQueryData(queryKeys.endpoint(endpoint.id), { data: endpoint })
    await queryClient.invalidateQueries({ queryKey: ['endpoints'] })
  }
}

// The API names the retry window in seconds; the forms ask for hours.
export function toEndpointFormError(error: unknown) {
  if (!(error instanceof ApiError) || !error.details?.retry_window_seconds) return error
  const { retry_window_seconds, ...details } = error.details
  const renamed = { ...details, retry_window_hours: retry_window_seconds }
  return new ApiError(error.status, error.code, error.message, renamed)
}

export function endpointQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.endpoint(id),
    queryFn: ({ signal }) => apiFetch<{ data: EndpointDetail }>(endpointPath(id), { signal }),
    select: (body) => body.data,
  })
}
