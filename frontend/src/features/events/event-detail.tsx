import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { LoadError } from '@/components/load-error'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { ApiError } from '@/lib/api/client'
import { useEndpointUrl, useMerchantName } from '@/lib/api/lookups'
import { formatDateTime } from '@/lib/format'
import { eventQueryOptions } from './queries'

// One event: its fields, its payload as text and its deliveries.
export function EventDetailView({ eventId }: { eventId: string }) {
  const query = useQuery(eventQueryOptions(eventId))
  const merchantName = useMerchantName()
  const endpointUrl = useEndpointUrl()

  if (query.isPending) return <Skeleton role="status" aria-label="Loading event" className="h-40" />
  if (query.error instanceof ApiError && query.error.status === 404) {
    return (
      <section>
        <h1 className="font-heading text-2xl font-semibold">Event not found</h1>
        <Link to="/events" className="mt-2 inline-block underline underline-offset-4">
          Back to the events
        </Link>
      </section>
    )
  }
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="The event could not be loaded." error={query.error} onRetry={retry} />
  }

  const event = query.data
  const fields = [
    ['Id', event.id],
    ['Merchant', merchantName(event.merchant_id)],
    ['Occurred', formatDateTime(event.occurred_at)],
    ['Received', formatDateTime(event.received_at)],
  ]

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Event {event.type}</h1>
      <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2 text-sm">
        {fields.map(([label, value]) => [<dt key="t">{label}</dt>, <dd key="d">{value}</dd>])}
      </dl>
      <h2 className="font-heading text-lg font-semibold">Payload</h2>
      {/* Rendered as text: the payload is never interpreted as HTML. */}
      <pre aria-label="Payload" className="overflow-x-auto rounded-lg bg-muted p-4 text-sm">
        {JSON.stringify(event.payload, null, 2)}
      </pre>
      <h2 className="font-heading text-lg font-semibold">Deliveries</h2>
      <ul aria-label="Deliveries" className="flex flex-col gap-2 text-sm">
        {event.deliveries.map((delivery) => (
          <li key={delivery.id} className="flex items-center gap-3">
            <Badge variant="outline">{delivery.status}</Badge>
            <span className="font-mono">{endpointUrl(delivery.endpoint_id)}</span>
            {/* A plain link until the delivery page's route exists (task 4.1). */}
            <a href={`/deliveries/${delivery.id}`} className="underline underline-offset-4">
              Delivery {delivery.id}
            </a>
          </li>
        ))}
      </ul>
    </section>
  )
}
