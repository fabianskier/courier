import { infiniteQueryOptions, queryOptions, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import type { Endpoint, MerchantDetail, Page } from '@/lib/api/types'

const merchantPath = (id: string) => `/merchants/${encodeURIComponent(id)}`

// Newest first; each page follows the previous page's `next_cursor`.
export function merchantsQueryOptions() {
  return infiniteQueryOptions({
    queryKey: queryKeys.merchantList,
    queryFn: ({ pageParam, signal }) =>
      apiFetch<Page<MerchantDetail>>('/merchants', { query: { cursor: pageParam }, signal }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (page) => page.next_cursor ?? undefined,
  })
}

export function merchantQueryOptions(id: string) {
  return queryOptions({
    queryKey: queryKeys.merchant(id),
    queryFn: ({ signal }) => apiFetch<{ data: MerchantDetail }>(merchantPath(id), { signal }),
    select: (body) => body.data,
  })
}

// A merchant's endpoints: the first 100, like the lookups (see design.md).
export function merchantEndpointsQueryOptions(merchantId: string) {
  const filters = { merchant_id: merchantId, limit: 100 }
  return queryOptions({
    queryKey: queryKeys.endpointList(filters),
    queryFn: ({ signal }) => apiFetch<Page<Endpoint>>('/endpoints', { query: filters, signal }),
    select: (page) => page.data,
  })
}

export const createMerchant = (name: string) =>
  apiFetch<{ data: MerchantDetail }>('/merchants', { method: 'POST', body: { name } })

export const updateMerchant = (id: string, changes: { name?: string; enabled?: boolean }) =>
  apiFetch<{ data: MerchantDetail }>(merchantPath(id), { method: 'PATCH', body: changes })

// After a change: the updated merchant is shown at once, and every merchant
// list and lookup is refetched so names and states stay current.
export function useMerchantSaved() {
  const queryClient = useQueryClient()
  return async (merchant: MerchantDetail) => {
    queryClient.setQueryData(queryKeys.merchant(merchant.id), { data: merchant })
    await queryClient.invalidateQueries({ queryKey: ['merchants'] })
  }
}
