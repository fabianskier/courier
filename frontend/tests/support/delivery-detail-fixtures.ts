import type { Attempt, DeliveryDetail } from '@/lib/api/types'
import { deliveryFixture } from './delivery-fixtures'

// Factories for a delivery's page: the delivery with its attempts and resends.
export const attemptFixture = (overrides: Partial<Attempt> = {}): Attempt => ({
  number: 1,
  started_at: '2026-11-01T10:00:00Z',
  duration_ms: 120,
  url: 'https://acme.test/hooks',
  response_status: 200,
  response_body: 'ok',
  error: null,
  ...overrides,
})

export const deliveryDetailFixture = (overrides: Partial<DeliveryDetail> = {}): DeliveryDetail => ({
  ...deliveryFixture(),
  window_ends_at: '2026-11-04T10:00:00Z',
  resends: [],
  attempts: [attemptFixture()],
  ...overrides,
})
