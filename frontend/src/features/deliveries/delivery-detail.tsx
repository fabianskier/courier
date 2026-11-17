import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { LoadError } from '@/components/load-error'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Skeleton } from '@/components/ui/skeleton'
import { ApiError } from '@/lib/api/client'
import { useEndpointUrl } from '@/lib/api/lookups'
import type { DeliveryDetail } from '@/lib/api/types'
import { formatDateTime, shortId } from '@/lib/format'
import { AttemptTimeline } from './attempt-timeline'
import { deliveryQueryOptions } from './queries'
import { ResendButton } from './resend-button'
import { StatusBadge } from './status-badge'

const link = 'font-mono underline underline-offset-4'

// One delivery: its summary, its state, its attempts and its resend links.
export function DeliveryDetailView({ deliveryId }: { deliveryId: string }) {
  const query = useQuery(deliveryQueryOptions(deliveryId))
  const endpointUrl = useEndpointUrl()

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading delivery" className="h-40" />
  if (query.error instanceof ApiError && query.error.status === 404) {
    return (
      <section>
        <h1 className="font-heading text-2xl font-semibold">Delivery not found</h1>
        <Link to="/deliveries" className="mt-2 inline-block underline underline-offset-4">
          Back to the deliveries
        </Link>
      </section>
    )
  }
  if (query.isError) {
    const retry = () => void query.refetch()
    return (
      <LoadError title="The delivery could not be loaded." error={query.error} onRetry={retry} />
    )
  }

  const delivery = query.data

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Delivery {shortId(delivery.id)}</h1>
      <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2 text-sm">
        <Field label="Id">
          <span className="font-mono">{delivery.id}</span>
        </Field>
        <Field label="Status">
          <StatusBadge status={delivery.status} />
        </Field>
        <Field label="Event">
          <Link to="/events/$eventId" params={{ eventId: delivery.event_id }} className={link}>
            {delivery.event_type ?? shortId(delivery.event_id)}
          </Link>
        </Field>
        <Field label="Endpoint">
          <span className="font-mono">{endpointUrl(delivery.endpoint_id)}</span>
        </Field>
        <Field label="Created">{formatDateTime(delivery.inserted_at)}</Field>
        <Field label="Completed">{formatDateTime(delivery.completed_at)}</Field>
        <Field label="Window ends">{formatDateTime(delivery.window_ends_at)}</Field>
        <Field label="Triggered by">
          <span className="font-mono">{delivery.triggered_by}</span>
        </Field>
        {delivery.resend_of_id && (
          <Field label="Resend of">
            <Link
              to="/deliveries/$deliveryId"
              params={{ deliveryId: delivery.resend_of_id }}
              className={link}
            >
              Delivery {shortId(delivery.resend_of_id)}
            </Link>
          </Field>
        )}
      </dl>
      <DeliveryState delivery={delivery} />
      <ResendButton
        key={delivery.id}
        delivery={delivery}
        endpointUrl={endpointUrl(delivery.endpoint_id)}
      />
      {delivery.status !== 'skipped' && (
        <>
          <h2 className="font-heading text-lg font-semibold">Attempts</h2>
          <AttemptTimeline attempts={delivery.attempts} />
        </>
      )}
      {delivery.resends.length > 0 && <Resends resends={delivery.resends} />}
    </section>
  )
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <>
      <dt>{label}</dt>
      <dd>{children}</dd>
    </>
  )
}

// What a pending or skipped delivery is waiting for, or why it was not sent.
function DeliveryState({ delivery }: { delivery: DeliveryDetail }) {
  if (delivery.status === 'pending') {
    return (
      <Alert>
        <AlertTitle>This delivery is pending.</AlertTitle>
        <AlertDescription>
          {delivery.next_attempt_at
            ? `Next attempt due ${formatDateTime(delivery.next_attempt_at)}.`
            : 'No attempt is scheduled yet.'}
        </AlertDescription>
      </Alert>
    )
  }
  if (delivery.status === 'skipped') {
    return (
      <Alert>
        <AlertTitle>This delivery was skipped.</AlertTitle>
        <AlertDescription>The endpoint's event filter excluded this event.</AlertDescription>
      </Alert>
    )
  }
  return null
}

// The direct resends of a delivery, oldest first, each linking to its page.
function Resends({ resends }: { resends: DeliveryDetail['resends'] }) {
  return (
    <>
      <h2 className="font-heading text-lg font-semibold">Resends</h2>
      <ul aria-label="Resends" className="flex flex-col gap-2 text-sm">
        {resends.map((resend) => (
          <li key={resend.id} className="flex flex-wrap items-center gap-3">
            <StatusBadge status={resend.status} />
            <span className="font-mono">{resend.triggered_by}</span>
            <span>{formatDateTime(resend.inserted_at)}</span>
            <Link to="/deliveries/$deliveryId" params={{ deliveryId: resend.id }} className={link}>
              Delivery {shortId(resend.id)}
            </Link>
          </li>
        ))}
      </ul>
    </>
  )
}
