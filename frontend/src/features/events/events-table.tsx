import { useInfiniteQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { LoadError } from '@/components/load-error'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import * as T from '@/components/ui/table'
import { useMerchantName } from '@/lib/api/lookups'
import { formatDateTime, shortId } from '@/lib/format'
import { type EventFilters, eventsQueryOptions } from './queries'

// The events matching `filters`, newest first, with "Load more".
export function EventsTable({ filters }: { filters: EventFilters }) {
  const query = useInfiniteQuery(eventsQueryOptions(filters))
  const merchantName = useMerchantName()

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading events" className="h-32" />
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="Events could not be loaded." error={query.error} onRetry={retry} />
  }

  const events = query.data.pages.flatMap((page) => page.data)
  if (events.length === 0) return <p className="text-muted-foreground">No events match.</p>
  const loadMore = () => void query.fetchNextPage()

  return (
    <div className="flex flex-col items-start gap-4">
      <T.Table>
        <T.TableHeader>
          <T.TableRow>
            <T.TableHead>Received</T.TableHead>
            <T.TableHead>Type</T.TableHead>
            <T.TableHead>Merchant</T.TableHead>
            <T.TableHead>Event</T.TableHead>
          </T.TableRow>
        </T.TableHeader>
        <T.TableBody>
          {events.map((event) => (
            <T.TableRow key={event.id}>
              <T.TableCell>{formatDateTime(event.received_at)}</T.TableCell>
              <T.TableCell className="font-mono">{event.type}</T.TableCell>
              <T.TableCell>{merchantName(event.merchant_id)}</T.TableCell>
              <T.TableCell>
                <Link
                  to="/events/$eventId"
                  params={{ eventId: event.id }}
                  className="font-mono underline underline-offset-4"
                >
                  {shortId(event.id)}
                </Link>
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
