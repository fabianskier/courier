import { createFileRoute } from '@tanstack/react-router'
import { EndpointFiltersForm } from '@/features/endpoints/endpoint-filters'
import { EndpointsTable } from '@/features/endpoints/endpoints-table'
import { endpointFiltersSchema } from '@/features/endpoints/queries'

export const Route = createFileRoute('/_app/endpoints/')({
  validateSearch: endpointFiltersSchema,
  component: Endpoints,
})

function Endpoints() {
  const filters = Route.useSearch()
  const navigate = Route.useNavigate()

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Endpoints</h1>
      <EndpointFiltersForm filters={filters} onChange={(search) => void navigate({ search })} />
      <EndpointsTable filters={filters} />
    </section>
  )
}
