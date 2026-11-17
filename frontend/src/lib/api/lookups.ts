import { useQuery } from '@tanstack/react-query'
import { shortId } from '@/lib/format'
import { apiFetch } from './client'
import { queryKeys } from './query-keys'
import type { Endpoint, Merchant, Page } from './types'

// One request each for merchant names and endpoint URLs, shared by every page
// instead of one request per row. Only the first 100 are known (see design.md).
function useLookup<T>(queryKey: readonly string[], path: string): T[] {
  const query = useQuery({
    queryKey,
    queryFn: ({ signal }) => apiFetch<Page<T>>(path, { query: { limit: 100 }, signal }),
    staleTime: 60_000,
  })
  return query.data?.data ?? []
}

export const useMerchants = () => useLookup<Merchant>(queryKeys.merchants, '/merchants')

// A merchant's name, or its shortened id while unknown.
export function useMerchantName() {
  const merchants = useMerchants()
  return (id: string) => merchants.find((m) => m.id === id)?.name ?? shortId(id)
}

export const useEndpoints = () => useLookup<Endpoint>(queryKeys.endpoints, '/endpoints')

// An endpoint's URL, or its shortened id while unknown.
export function useEndpointUrl() {
  const endpoints = useEndpoints()
  return (id: string) => endpoints.find((e) => e.id === id)?.url ?? shortId(id)
}
