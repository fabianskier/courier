// Every TanStack Query key of the dashboard, built in one place.
export const queryKeys = {
  me: ['me'] as const,
  merchants: ['merchants', 'lookup'] as const,
  endpoints: ['endpoints', 'lookup'] as const,
  events: {
    list: (filters: object) => ['events', 'list', filters] as const,
    detail: (id: string) => ['events', 'detail', id] as const,
  },
}
