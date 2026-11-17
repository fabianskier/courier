import { Field, FieldLabel } from '@/components/ui/field'
import * as S from '@/components/ui/select'
import { useMerchants } from '@/lib/api/lookups'
import type { EndpointFilters } from './queries'

// Radix Select has no empty value: this one stands for "any".
const ANY = 'any'

type Props = { filters: EndpointFilters; onChange: (filters: EndpointFilters) => void }

// Applied as soon as they change; the page keeps them in its URL.
export function EndpointFiltersForm({ filters, onChange }: Props) {
  const merchants = useMerchants()

  return (
    <div role="group" aria-label="Endpoint filters" className="flex flex-wrap items-end gap-6">
      <Field className="w-56">
        <FieldLabel htmlFor="endpoint-merchant_id">Merchant</FieldLabel>
        <S.Select
          value={filters.merchant_id ?? ANY}
          onValueChange={(v) => onChange({ ...filters, merchant_id: v === ANY ? undefined : v })}
        >
          <S.SelectTrigger id="endpoint-merchant_id" className="w-full">
            <S.SelectValue />
          </S.SelectTrigger>
          <S.SelectContent>
            <S.SelectItem value={ANY}>All merchants</S.SelectItem>
            {merchants.map((m) => (
              <S.SelectItem key={m.id} value={m.id}>
                {m.name}
              </S.SelectItem>
            ))}
          </S.SelectContent>
        </S.Select>
      </Field>
      <label className="flex h-9 items-center gap-2 text-sm">
        <input
          type="checkbox"
          className="size-4 accent-primary"
          checked={filters.degraded === true}
          onChange={(e) => onChange({ ...filters, degraded: e.target.checked || undefined })}
        />
        Degraded only
      </label>
    </div>
  )
}
