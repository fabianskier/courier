import { createFileRoute } from '@tanstack/react-router'
import { EventFiltersForm } from '@/features/events/event-filters'
import { EventsTable } from '@/features/events/events-table'
import { eventFiltersSchema } from '@/features/events/queries'

export const Route = createFileRoute('/_app/events/')({
  validateSearch: eventFiltersSchema,
  component: Events,
})

function Events() {
  const filters = Route.useSearch()
  const navigate = Route.useNavigate()

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Events</h1>
      <EventFiltersForm filters={filters} onApply={(search) => void navigate({ search })} />
      <EventsTable filters={filters} />
    </section>
  )
}
