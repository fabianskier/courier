import { Controller, useForm } from 'react-hook-form'
import { Button } from '@/components/ui/button'
import { Field, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import * as S from '@/components/ui/select'
import { useMerchants } from '@/lib/api/lookups'
import { fromLocalInput, toLocalInput } from '@/lib/format'
import type { EventFilters } from './queries'

// Radix Select has no empty value: this one stands for "any merchant".
const ANY = 'any'

// Every field is free text; the route's search schema drops what is invalid.
type Values = Record<'merchant_id' | 'type' | 'since' | 'until', string>

const toValues = (filters: EventFilters): Values => ({
  merchant_id: filters.merchant_id ?? '',
  type: filters.type ?? '',
  since: toLocalInput(filters.since),
  until: toLocalInput(filters.until),
})

const toFilters = (values: Values): EventFilters => ({
  merchant_id: values.merchant_id || undefined,
  type: values.type.trim() || undefined,
  since: fromLocalInput(values.since),
  until: fromLocalInput(values.until),
})

const inputs = [
  { name: 'type', label: 'Type', type: 'text' },
  { name: 'since', label: 'Received from', type: 'datetime-local' },
  { name: 'until', label: 'Received before', type: 'datetime-local' },
] as const

type Props = { filters: EventFilters; onApply: (filters: EventFilters) => void }

// Applied on submit; the page keeps the filters in its URL.
export function EventFiltersForm({ filters, onApply }: Props) {
  const merchants = useMerchants()
  const form = useForm<Values>({ values: toValues(filters) })
  const clear = () => {
    form.reset(toValues({}))
    onApply({})
  }

  return (
    <form
      aria-label="Event filters"
      onSubmit={form.handleSubmit((values) => onApply(toFilters(values)))}
      className="flex flex-wrap items-end gap-4"
    >
      <Field className="w-56">
        <FieldLabel htmlFor="event-merchant">Merchant</FieldLabel>
        <Controller
          control={form.control}
          name="merchant_id"
          render={({ field }) => (
            <S.Select
              value={field.value || ANY}
              onValueChange={(v) => field.onChange(v === ANY ? '' : v)}
            >
              <S.SelectTrigger id="event-merchant" className="w-full">
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
          )}
        />
      </Field>
      {inputs.map(({ name, label, type }) => (
        <Field key={name} className="w-56">
          <FieldLabel htmlFor={`event-${name}`}>{label}</FieldLabel>
          <Input id={`event-${name}`} type={type} {...form.register(name)} />
        </Field>
      ))}
      <Button type="submit">Apply</Button>
      <Button type="button" variant="outline" onClick={clear}>
        Clear
      </Button>
    </form>
  )
}
