import { createFileRoute } from '@tanstack/react-router'
import { WriteScopeNote } from '@/components/write-scope-note'
import { useCanWrite } from '@/features/auth/session'
import { MerchantsTable } from '@/features/merchants/merchants-table'
import { NewMerchantDialog } from '@/features/merchants/new-merchant-dialog'

export const Route = createFileRoute('/_app/merchants/')({
  component: Merchants,
})

function Merchants() {
  const canWrite = useCanWrite()

  return (
    <section className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-heading text-2xl font-semibold">Merchants</h1>
        {canWrite ? <NewMerchantDialog /> : <WriteScopeNote />}
      </div>
      <MerchantsTable />
    </section>
  )
}
