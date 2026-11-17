import type { Endpoint, EventDetail, Merchant, Page } from '@/lib/api/types'

// Factories for events, merchants and endpoints (fixtures.ts is protected).
let sequence = 0
const uuid = () => `${String(++sequence).padStart(8, '0')}-0000-4000-8000-000000000000`

export const merchantFixture = (name: string): Merchant => ({ id: uuid(), name })

export const endpointFixture = (url: string): Endpoint => ({ id: uuid(), merchant_id: uuid(), url })

export const eventFixture = (overrides: Partial<EventDetail> = {}): EventDetail => ({
  id: uuid(),
  type: 'payment.succeeded',
  merchant_id: uuid(),
  payload: { amount: 1200 },
  occurred_at: '2026-11-01T09:59:00Z',
  received_at: '2026-11-01T10:00:00Z',
  deliveries: [],
  ...overrides,
})

export const pageOf = <T>(data: T[], next_cursor: string | null = null): Page<T> => ({
  data,
  next_cursor,
})
