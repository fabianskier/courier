import { useInfiniteQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { LoadError } from '@/components/load-error'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import * as T from '@/components/ui/table'
import { formatDateTime } from '@/lib/format'
import { MerchantState } from './merchant-state'
import { merchantsQueryOptions } from './queries'

// Every merchant, newest first, with "Load more".
export function MerchantsTable() {
  const query = useInfiniteQuery(merchantsQueryOptions())

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading merchants" className="h-32" />
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="Merchants could not be loaded." error={query.error} onRetry={retry} />
  }

  const merchants = query.data.pages.flatMap((page) => page.data)
  if (merchants.length === 0) return <p className="text-muted-foreground">No merchants yet.</p>
  const loadMore = () => void query.fetchNextPage()

  return (
    <div className="flex flex-col items-start gap-4">
      <T.Table>
        <T.TableHeader>
          <T.TableRow>
            <T.TableHead>Name</T.TableHead>
            <T.TableHead>State</T.TableHead>
            <T.TableHead>Created</T.TableHead>
          </T.TableRow>
        </T.TableHeader>
        <T.TableBody>
          {merchants.map((merchant) => (
            <T.TableRow key={merchant.id}>
              <T.TableCell>
                <Link
                  to="/merchants/$merchantId"
                  params={{ merchantId: merchant.id }}
                  className="underline underline-offset-4"
                >
                  {merchant.name}
                </Link>
              </T.TableCell>
              <T.TableCell>
                <MerchantState enabled={merchant.enabled} />
              </T.TableCell>
              <T.TableCell>{formatDateTime(merchant.inserted_at)}</T.TableCell>
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
