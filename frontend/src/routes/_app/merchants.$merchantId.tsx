import { createFileRoute } from '@tanstack/react-router'
import { MerchantDetailView } from '@/features/merchants/merchant-detail'

export const Route = createFileRoute('/_app/merchants/$merchantId')({
  component: MerchantPage,
})

function MerchantPage() {
  const { merchantId } = Route.useParams()
  return <MerchantDetailView merchantId={merchantId} />
}
