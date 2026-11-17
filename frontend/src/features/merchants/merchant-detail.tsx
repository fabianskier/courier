import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { toast } from 'sonner'
import { LoadError } from '@/components/load-error'
import { Skeleton } from '@/components/ui/skeleton'
import { WriteScopeNote } from '@/components/write-scope-note'
import { useCanWrite } from '@/features/auth/session'
import { ApiError } from '@/lib/api/client'
import type { MerchantDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { MerchantNameForm } from './merchant-name-form'
import { MerchantState } from './merchant-state'
import { MerchantToggle } from './merchant-toggle'
import {
  merchantEndpointsQueryOptions,
  merchantQueryOptions,
  updateMerchant,
  useMerchantSaved,
} from './queries'

// One merchant: name and state, rename and disable/enable (write), endpoints.
export function MerchantDetailView({ merchantId }: { merchantId: string }) {
  const query = useQuery(merchantQueryOptions(merchantId))

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading merchant" className="h-40" />
  if (query.error instanceof ApiError && query.error.status === 404) {
    return (
      <section>
        <h1 className="font-heading text-2xl font-semibold">Merchant not found</h1>
        <Link to="/merchants" className="mt-2 inline-block underline underline-offset-4">
          Back to the merchants
        </Link>
      </section>
    )
  }
  if (query.isError) {
    const retry = () => void query.refetch()
    return (
      <LoadError title="The merchant could not be loaded." error={query.error} onRetry={retry} />
    )
  }

  const merchant = query.data
  return (
    <section className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="font-heading text-2xl font-semibold">{merchant.name}</h1>
        <MerchantState enabled={merchant.enabled} />
      </div>
      <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2 text-sm">
        <dt>Id</dt>
        <dd className="font-mono">{merchant.id}</dd>
        <dt>Created</dt>
        <dd>{formatDateTime(merchant.inserted_at)}</dd>
      </dl>
      <MerchantActions merchant={merchant} />
      <h2 className="font-heading text-lg font-semibold">Endpoints</h2>
      <MerchantEndpoints merchantId={merchant.id} />
    </section>
  )
}

function MerchantActions({ merchant }: { merchant: MerchantDetail }) {
  const canWrite = useCanWrite()
  const saved = useMerchantSaved()

  if (!canWrite) return <WriteScopeNote />
  return (
    <div className="flex flex-col gap-6">
      <MerchantToggle merchant={merchant} />
      <div className="flex flex-col gap-2">
        <h2 className="font-heading text-lg font-semibold">Rename</h2>
        <MerchantNameForm
          // A new key resets the form to the saved name.
          key={merchant.name}
          id="merchant-name"
          defaultName={merchant.name}
          submitLabel="Rename"
          save={(name) => updateMerchant(merchant.id, { name })}
          onSaved={async (updated) => {
            await saved(updated)
            toast.success('Merchant renamed')
          }}
        />
      </div>
    </div>
  )
}

// Until the endpoint pages exist, each endpoint is shown by its URL.
function MerchantEndpoints({ merchantId }: { merchantId: string }) {
  const query = useQuery(merchantEndpointsQueryOptions(merchantId))

  if (query.isPending)
    return <Skeleton role="status" aria-label="Loading endpoints" className="h-16" />
  if (query.isError) {
    const retry = () => void query.refetch()
    return <LoadError title="Endpoints could not be loaded." error={query.error} onRetry={retry} />
  }
  if (query.data.length === 0) return <p className="text-muted-foreground">No endpoints yet.</p>

  return (
    <ul aria-label="Endpoints" className="flex flex-col gap-2 text-sm">
      {query.data.map((endpoint) => (
        <li key={endpoint.id} className="font-mono break-all">
          {endpoint.url}
        </li>
      ))}
    </ul>
  )
}
