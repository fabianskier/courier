import { createFileRoute } from '@tanstack/react-router'
import { z } from 'zod'
import { WriteScopeNote } from '@/components/write-scope-note'
import { useCanWrite } from '@/features/auth/session'
import { NewEndpointForm } from '@/features/endpoints/new-endpoint-form'

// `merchant_id` preselects the merchant (the merchant page's "New endpoint").
const searchSchema = z.object({
  merchant_id: z.string().min(1).optional().catch(undefined),
})

export const Route = createFileRoute('/_app/endpoints/new')({
  validateSearch: searchSchema,
  component: NewEndpoint,
})

function NewEndpoint() {
  const { merchant_id } = Route.useSearch()
  const canWrite = useCanWrite()

  return (
    <section className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">New endpoint</h1>
      {canWrite ? <NewEndpointForm merchantId={merchant_id} /> : <WriteScopeNote />}
    </section>
  )
}
