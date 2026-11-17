import { useInfiniteQuery } from '@tanstack/react-query'
import { LoadError } from '@/components/load-error'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import * as T from '@/components/ui/table'
import { useEndpointUrl } from '@/lib/api/lookups'
import { formatDateTime, shortId } from '@/lib/format'
import { type DeliveryFilters, deliveriesQueryOptions } from './queries'
import { StatusBadge } from './status-badge'

type Props = { filters: DeliveryFilters; emptyMessage: string }

// The deliveries matching `filters`, newest first, with "Load more".
export function DeliveriesTable({ filters, emptyMessage }: Props) {
  const query = useInfiniteQuery(deliveriesQueryOptions(filters))
  const endpointUrl = useEndpointUrl()

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading deliveries" className="h-32" />
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="Deliveries could not be loaded." error={query.error} onRetry={retry} />
  }

  const deliveries = query.data.pages.flatMap((page) => page.data)
  if (deliveries.length === 0) return <p className="text-muted-foreground">{emptyMessage}</p>
  const loadMore = () => void query.fetchNextPage()

  return (
    <div className="flex flex-col items-start gap-4">
      <T.Table>
        <T.TableHeader>
          <T.TableRow>
            <T.TableHead>Created</T.TableHead>
            <T.TableHead>Status</T.TableHead>
            <T.TableHead>Event type</T.TableHead>
            <T.TableHead>Endpoint</T.TableHead>
            <T.TableHead>Attempts</T.TableHead>
            <T.TableHead>Delivery</T.TableHead>
          </T.TableRow>
        </T.TableHeader>
        <T.TableBody>
          {deliveries.map((delivery) => (
            <T.TableRow key={delivery.id}>
              <T.TableCell>{formatDateTime(delivery.inserted_at)}</T.TableCell>
              <T.TableCell>
                <StatusBadge status={delivery.status} />
              </T.TableCell>
              <T.TableCell className="font-mono">{delivery.event_type ?? '—'}</T.TableCell>
              <T.TableCell className="font-mono">{endpointUrl(delivery.endpoint_id)}</T.TableCell>
              <T.TableCell>{delivery.attempt_count}</T.TableCell>
              <T.TableCell>
                {/* A plain link until the delivery page's route exists (task 4.1). */}
                <a
                  href={`/deliveries/${delivery.id}`}
                  className="font-mono underline underline-offset-4"
                >
                  {shortId(delivery.id)}
                </a>
              </T.TableCell>
            </T.TableRow>
          ))}
        </T.TableBody>
      </T.Table>
      {query.hasNextPage && (
        <Button variant="outline" onClick={loadMore} disabled={query.isFetchingNextPage}>
          Load more
        </Button>
      )}
    </div>
  )
}
