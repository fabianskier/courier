import { createFileRoute } from '@tanstack/react-router'
import { DeliveriesTable } from '@/features/deliveries/deliveries-table'
import { DeliveryFiltersForm } from '@/features/deliveries/delivery-filters'
import { deliveryFiltersSchema } from '@/features/deliveries/queries'

export const Route = createFileRoute('/_app/deliveries/')({
  validateSearch: deliveryFiltersSchema,
  component: Deliveries,
})

function Deliveries() {
  const filters = Route.useSearch()
  const navigate = Route.useNavigate()

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Deliveries</h1>
      <DeliveryFiltersForm filters={filters} onApply={(search) => void navigate({ search })} />
      <DeliveriesTable filters={filters} emptyMessage="No deliveries match." />
    </section>
  )
}
