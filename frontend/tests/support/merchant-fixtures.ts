import type { MerchantDetail } from '@/lib/api/types'

// Merchants as the merchants API renders them (fixtures.ts is protected).
let sequence = 0

export const merchantDetailFixture = (overrides: Partial<MerchantDetail> = {}): MerchantDetail => {
  const id = `m${String(++sequence).padStart(7, '0')}-0000-4000-8000-000000000000`
  return {
    id,
    name: 'Acme',
    enabled: true,
    inserted_at: '2026-11-01T10:00:00Z',
    updated_at: '2026-11-01T10:00:00Z',
    ...overrides,
  }
}
