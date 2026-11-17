import { infiniteQueryOptions, queryOptions } from '@tanstack/react-query'
import { z } from 'zod'
import { apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import type { CourierEvent, EventDetail, Page } from '@/lib/api/types'

// The events list's URL search: unknown or invalid values are dropped.
export const eventFiltersSchema = z.object({
  merchant_id: z.string().min(1).optional().catch(undefined),
  type: z.string().min(1).optional().catch(undefined),
  since: z.iso.datetime({ offset: true }).optional().catch(undefined),
  until: z.iso.datetime({ offset: true }).optional().catch(undefined),
})

export type EventFilters = z.infer<typeof eventFiltersSchema>

// Newest first; each page follows the previous page's `next_cursor`.
export function eventsQueryOptions(filters: EventFilters) {
  return infiniteQueryOptions({
    queryKey: queryKeys.events.list(filters),
    queryFn: ({ pageParam, signal }) =>
      apiFetch<Page<CourierEvent>>('/events', { query: { ...filters, cursor: pageParam }, signal }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (page) => page.next_cursor ?? undefined,
  })
}

export function eventQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.events.detail(id),
    queryFn: ({ signal }) =>
      apiFetch<{ data: EventDetail }>(`/events/${encodeURIComponent(id)}`, { signal }),
    select: (body) => body.data,
  })
}
