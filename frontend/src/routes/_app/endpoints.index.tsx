import { createFileRoute, Link } from '@tanstack/react-router'
import { Button } from '@/components/ui/button'
import { WriteScopeNote } from '@/components/write-scope-note'
import { useCanWrite } from '@/features/auth/session'
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
  const canWrite = useCanWrite()

  return (
    <section className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-heading text-2xl font-semibold">Endpoints</h1>
        {canWrite ? (
          <Button asChild size="sm">
            <Link to="/endpoints/new" search={{ merchant_id: filters.merchant_id }}>
              New endpoint
            </Link>
          </Button>
        ) : (
          <WriteScopeNote />
        )}
      </div>
      <EndpointFiltersForm filters={filters} onChange={(search) => void navigate({ search })} />
      <EndpointsTable filters={filters} />
    </section>
  )
}
