// Every TanStack Query key of the dashboard, built in one place.
export const queryKeys = {
  me: ['me'] as const,
  merchants: ['merchants', 'lookup'] as const,
  endpoints: ['endpoints', 'lookup'] as const,
  // Under the lookups' `merchants` / `endpoints` prefixes: invalidating a
  // prefix after a change refreshes lookups, lists and details together.
  merchantList: ['merchants', 'list'] as const,
  merchant: (id: string) => ['merchants', 'detail', id] as const,
  endpointList: (filters: object) => ['endpoints', 'list', filters] as const,
  events: {
    list: (filters: object) => ['events', 'list', filters] as const,
    detail: (id: string) => ['events', 'detail', id] as const,
  },
  deliveries: {
    list: (filters: object) => ['deliveries', 'list', filters] as const,
    detail: (id: string) => ['deliveries', 'detail', id] as const,
  },
}
