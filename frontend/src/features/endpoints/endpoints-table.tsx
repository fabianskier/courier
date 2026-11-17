import { useInfiniteQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { LoadError } from '@/components/load-error'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import * as T from '@/components/ui/table'
import { MerchantState } from '@/features/merchants/merchant-state'
import { useMerchantName } from '@/lib/api/lookups'
import { HealthBadge } from './health-badge'
import { type EndpointFilters, endpointsQueryOptions } from './queries'

// The endpoints matching `filters`, with "Load more".
export function EndpointsTable({ filters }: { filters: EndpointFilters }) {
  const query = useInfiniteQuery(endpointsQueryOptions(filters))
  const merchantName = useMerchantName()

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading endpoints" className="h-32" />
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="Endpoints could not be loaded." error={query.error} onRetry={retry} />
  }

  const endpoints = query.data.pages.flatMap((page) => page.data)
  if (endpoints.length === 0) return <p className="text-muted-foreground">No endpoints match.</p>
  const loadMore = () => void query.fetchNextPage()

  return (
    <div className="flex flex-col items-start gap-4">
      <T.Table>
        <T.TableHeader>
          <T.TableRow>
            <T.TableHead>URL</T.TableHead>
            <T.TableHead>Merchant</T.TableHead>
            <T.TableHead>State</T.TableHead>
            <T.TableHead>Health</T.TableHead>
          </T.TableRow>
        </T.TableHeader>
        <T.TableBody>
          {endpoints.map((endpoint) => (
            <T.TableRow key={endpoint.id}>
              <T.TableCell className="font-mono break-all whitespace-normal">
                <Link
                  to="/endpoints/$endpointId"
                  params={{ endpointId: endpoint.id }}
                  className="underline underline-offset-4"
                >
                  {endpoint.url}
                </Link>
              </T.TableCell>
              <T.TableCell>{merchantName(endpoint.merchant_id)}</T.TableCell>
              <T.TableCell>
                <MerchantState enabled={endpoint.enabled} />
              </T.TableCell>
              <T.TableCell>
                <HealthBadge
                  degraded={endpoint.degraded}
                  consecutiveFailures={endpoint.consecutive_failures}
                />
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
