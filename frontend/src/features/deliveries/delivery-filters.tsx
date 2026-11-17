import { type Control, Controller, useForm } from 'react-hook-form'
import { Button } from '@/components/ui/button'
import { Field, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import * as S from '@/components/ui/select'
import { useEndpoints, useMerchants } from '@/lib/api/lookups'
import { fromLocalInput, toLocalInput } from '@/lib/format'
import { type DeliveryFilters, deliveryStatuses } from './queries'

// Radix Select has no empty value: this one stands for "any".
const ANY = 'any'

// Every field is free text; the route's search schema drops what is invalid.
type Name = 'status' | 'merchant_id' | 'endpoint_id' | 'event_type' | 'since' | 'until'
type Values = Record<Name, string>

const toValues = (filters: DeliveryFilters): Values => ({
  status: filters.status ?? '',
  merchant_id: filters.merchant_id ?? '',
  endpoint_id: filters.endpoint_id ?? '',
  event_type: filters.event_type ?? '',
  since: toLocalInput(filters.since),
  until: toLocalInput(filters.until),
})

const toFilters = (values: Values): DeliveryFilters => ({
  status: (values.status || undefined) as DeliveryFilters['status'],
  merchant_id: values.merchant_id || undefined,
  endpoint_id: values.endpoint_id || undefined,
  event_type: values.event_type.trim() || undefined,
  since: fromLocalInput(values.since),
  until: fromLocalInput(values.until),
})

const inputs = [
  { name: 'event_type', label: 'Event type', type: 'text' },
  { name: 'since', label: 'Created from', type: 'datetime-local' },
  { name: 'until', label: 'Created before', type: 'datetime-local' },
] as const

type Option = { value: string; label: string }
type SelectProps = {
  control: Control<Values>
  name: Name
  label: string
  anyLabel: string
  options: Option[]
}

function FilterSelect({ control, name, label, anyLabel, options }: SelectProps) {
  return (
    <Field className="w-56">
      <FieldLabel htmlFor={`delivery-${name}`}>{label}</FieldLabel>
      <Controller
        control={control}
        name={name}
        render={({ field }) => (
          <S.Select
            value={field.value || ANY}
            onValueChange={(v) => field.onChange(v === ANY ? '' : v)}
          >
            <S.SelectTrigger id={`delivery-${name}`} className="w-full">
              <S.SelectValue />
            </S.SelectTrigger>
            <S.SelectContent>
              <S.SelectItem value={ANY}>{anyLabel}</S.SelectItem>
              {options.map((o) => (
                <S.SelectItem key={o.value} value={o.value}>
                  {o.label}
                </S.SelectItem>
              ))}
            </S.SelectContent>
          </S.Select>
        )}
      />
    </Field>
  )
}

type Props = {
  filters: DeliveryFilters
  onApply: (filters: DeliveryFilters) => void
  // The failed view fixes the status and hides its filter.
  withStatus?: boolean
}

// Applied on submit; the page keeps the filters in its URL.
export function DeliveryFiltersForm({ filters, onApply, withStatus = true }: Props) {
  const merchants = useMerchants().map((m) => ({ value: m.id, label: m.name }))
  const endpoints = useEndpoints().map((e) => ({ value: e.id, label: e.url }))
  const statuses = deliveryStatuses.map((s) => ({ value: s, label: s }))
  const form = useForm<Values>({ values: toValues(filters) })
  const clear = () => {
    form.reset(toValues({}))
    onApply({})
  }
  const control = form.control

  return (
    <form
      aria-label="Delivery filters"
      onSubmit={form.handleSubmit((values) => onApply(toFilters(values)))}
      className="flex flex-wrap items-end gap-4"
    >
      {withStatus && (
        <FilterSelect
          control={control}
          name="status"
          label="Status"
          anyLabel="All statuses"
          options={statuses}
        />
      )}
      <FilterSelect
        control={control}
        name="merchant_id"
        label="Merchant"
        anyLabel="All merchants"
        options={merchants}
      />
      <FilterSelect
        control={control}
        name="endpoint_id"
        label="Endpoint"
        anyLabel="All endpoints"
        options={endpoints}
      />
      {inputs.map(({ name, label, type }) => (
        <Field key={name} className="w-56">
          <FieldLabel htmlFor={`delivery-${name}`}>{label}</FieldLabel>
          <Input id={`delivery-${name}`} type={type} {...form.register(name)} />
        </Field>
      ))}
      <Button type="submit">Apply</Button>
      <Button type="button" variant="outline" onClick={clear}>
        Clear
      </Button>
    </form>
  )
}
