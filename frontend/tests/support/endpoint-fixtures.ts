import type { EndpointDetail } from '@/lib/api/types'

// Endpoints as the endpoints API renders them (fixtures.ts is protected).
let sequence = 0

export const endpointDetailFixture = (overrides: Partial<EndpointDetail> = {}): EndpointDetail => {
  const n = String(++sequence).padStart(7, '0')
  return {
    id: `e${n}-0000-4000-8000-000000000000`,
    merchant_id: 'm0000000-0000-4000-8000-000000000000',
    url: `https://hooks.test/${n}`,
    description: null,
    event_types: [],
    enabled: true,
    retry_window_seconds: 86_400,
    retry_on_4xx: false,
    max_concurrency: 10,
    consecutive_failures: 0,
    degraded: false,
    degraded_at: null,
    previous_secret_expires_at: null,
    inserted_at: '2026-11-01T10:00:00Z',
    updated_at: '2026-11-01T10:00:00Z',
    ...overrides,
  }
}

// A degraded endpoint with `failures` consecutive failures.
export const degradedEndpointFixture = (
  failures: number,
  overrides: Partial<EndpointDetail> = {},
): EndpointDetail =>
  endpointDetailFixture({
    consecutive_failures: failures,
    degraded: true,
    degraded_at: '2026-11-03T07:15:00Z',
    ...overrides,
  })
