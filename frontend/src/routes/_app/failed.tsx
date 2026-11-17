import { createFileRoute } from '@tanstack/react-router'
import { DeliveriesTable } from '@/features/deliveries/deliveries-table'
import { DeliveryFiltersForm } from '@/features/deliveries/delivery-filters'
import { failedFiltersSchema } from '@/features/deliveries/queries'

export const Route = createFileRoute('/_app/failed')({
  validateSearch: failedFiltersSchema,
  component: Failed,
})

// The deliveries list with the status fixed to `failed`.
function Failed() {
  const filters = Route.useSearch()
  const navigate = Route.useNavigate()
  const applied = { ...filters, status: 'failed' as const }

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Failed deliveries</h1>
      <DeliveryFiltersForm
        filters={filters}
        withStatus={false}
        onApply={(search) => void navigate({ search: failedFiltersSchema.parse(search) })}
      />
      <DeliveriesTable filters={applied} emptyMessage="No deliveries have failed." />
    </section>
  )
}
