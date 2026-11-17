import { infiniteQueryOptions, queryOptions } from '@tanstack/react-query'
import { z } from 'zod'
import { apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import type { DeliveryDetail, DeliverySummary, Page } from '@/lib/api/types'

export const deliveryStatuses = ['pending', 'succeeded', 'failed', 'skipped'] as const

// The deliveries list's URL search: unknown or invalid values are dropped.
export const deliveryFiltersSchema = z.object({
  status: z.enum(deliveryStatuses).optional().catch(undefined),
  merchant_id: z.string().min(1).optional().catch(undefined),
  endpoint_id: z.string().min(1).optional().catch(undefined),
  event_type: z.string().min(1).optional().catch(undefined),
  since: z.iso.datetime({ offset: true }).optional().catch(undefined),
  until: z.iso.datetime({ offset: true }).optional().catch(undefined),
})

// The failed view: the same filters, with the status fixed by the page.
export const failedFiltersSchema = deliveryFiltersSchema.omit({ status: true })

export type DeliveryFilters = z.infer<typeof deliveryFiltersSchema>

// Newest first; each page follows the previous page's `next_cursor`.
export function deliveriesQueryOptions(filters: DeliveryFilters) {
  return infiniteQueryOptions({
    queryKey: queryKeys.deliveries.list(filters),
    queryFn: ({ pageParam, signal }) =>
      apiFetch<Page<DeliverySummary>>('/deliveries', {
        query: { ...filters, cursor: pageParam },
        signal,
      }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (page) => page.next_cursor ?? undefined,
  })
}

export function deliveryQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.deliveries.detail(id),
    queryFn: ({ signal }) =>
      apiFetch<{ data: DeliveryDetail }>(`/deliveries/${encodeURIComponent(id)}`, { signal }),
    select: (body) => body.data,
  })
}
