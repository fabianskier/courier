import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { LoadError } from '@/components/load-error'
import { Skeleton } from '@/components/ui/skeleton'
import { MerchantState } from '@/features/merchants/merchant-state'
import { ApiError } from '@/lib/api/client'
import { useMerchantName } from '@/lib/api/lookups'
import type { EndpointDetail } from '@/lib/api/types'
import { formatDateTime, formatRetryWindow } from '@/lib/format'
import { HealthBadge } from './health-badge'
import { endpointQueryOptions } from './queries'

// One endpoint, read-only: details, settings, health, secret overlap and a
// link to its deliveries.
export function EndpointDetailView({ endpointId }: { endpointId: string }) {
  const query = useQuery(endpointQueryOptions(endpointId))

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading endpoint" className="h-40" />
  if (query.error instanceof ApiError && query.error.status === 404) {
    return (
      <section>
        <h1 className="font-heading text-2xl font-semibold">Endpoint not found</h1>
        <Link to="/endpoints" className="mt-2 inline-block underline underline-offset-4">
          Back to the endpoints
        </Link>
      </section>
    )
  }
  if (query.isError) {
    const retry = () => void query.refetch()
    return (
      <LoadError title="The endpoint could not be loaded." error={query.error} onRetry={retry} />
    )
  }

  const endpoint = query.data
  return (
    <section className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="font-heading text-2xl font-semibold break-all">{endpoint.url}</h1>
        <MerchantState enabled={endpoint.enabled} />
      </div>
      <EndpointFacts endpoint={endpoint} />
      <Link
        to="/deliveries"
        search={{ endpoint_id: endpoint.id }}
        className="self-start underline underline-offset-4"
      >
        Deliveries of this endpoint
      </Link>
    </section>
  )
}

function EndpointFacts({ endpoint }: { endpoint: EndpointDetail }) {
  const merchantName = useMerchantName()
  const filters = endpoint.event_types

  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2 text-sm">
      <dt>Id</dt>
      <dd className="font-mono">{endpoint.id}</dd>
      <dt>Merchant</dt>
      <dd>
        <Link
          to="/merchants/$merchantId"
          params={{ merchantId: endpoint.merchant_id }}
          className="underline underline-offset-4"
        >
          {merchantName(endpoint.merchant_id)}
        </Link>
      </dd>
      <dt>Description</dt>
      <dd>{endpoint.description || '—'}</dd>
      <dt>Event types</dt>
      <dd>
        {filters.length === 0 ? (
          'All event types'
        ) : (
          <ul aria-label="Event types" className="flex flex-wrap gap-2 font-mono">
            {filters.map((type) => (
              <li key={type}>{type}</li>
            ))}
          </ul>
        )}
      </dd>
      <dt>Retry window</dt>
      <dd>{formatRetryWindow(endpoint.retry_window_seconds)}</dd>
      <dt>Retry on 4xx</dt>
      <dd>{endpoint.retry_on_4xx ? 'Yes' : 'No'}</dd>
      <dt>Concurrency</dt>
      <dd>{endpoint.max_concurrency}</dd>
      <dt>Health</dt>
      <dd>
        <HealthBadge
          degraded={endpoint.degraded}
          consecutiveFailures={endpoint.consecutive_failures}
        />
      </dd>
      {endpoint.degraded && (
        <>
          <dt>Degraded since</dt>
          <dd>{formatDateTime(endpoint.degraded_at)}</dd>
        </>
      )}
      {endpoint.previous_secret_expires_at && (
        <>
          <dt>Previous secret</dt>
          <dd>Signs until {formatDateTime(endpoint.previous_secret_expires_at)}</dd>
        </>
      )}
      <dt>Created</dt>
      <dd>{formatDateTime(endpoint.inserted_at)}</dd>
    </dl>
  )
}
