import type { ApiErrorBody, Me } from '@/lib/api/types'

// Factories for API responses; later tasks add events, deliveries, attempts,
// merchants and endpoints.
export function meFixture(overrides: Partial<Me> = {}): Me {
  return { name: 'demo', scopes: ['read', 'write'], ...overrides }
}

export function errorFixture(code: string, message: string): ApiErrorBody {
  return { error: { code, message } }
}
