import type { DeliverySummary } from '@/lib/api/types'

// Factories for deliveries; ids start with `d` so their short ids are distinct.
let sequence = 0
const uuid = () => `d${String(++sequence).padStart(7, '0')}-0000-4000-8000-000000000000`

export const deliveryFixture = (overrides: Partial<DeliverySummary> = {}): DeliverySummary => ({
  id: uuid(),
  event_id: uuid(),
  event_type: 'payment.succeeded',
  merchant_id: uuid(),
  endpoint_id: uuid(),
  status: 'succeeded',
  attempt_count: 1,
  next_attempt_at: null,
  completed_at: '2026-11-01T10:00:01Z',
  resend_of_id: null,
  triggered_by: 'system',
  inserted_at: '2026-11-01T10:00:00Z',
  ...overrides,
})
