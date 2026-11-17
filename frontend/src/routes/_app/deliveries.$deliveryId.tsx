import { createFileRoute } from '@tanstack/react-router'
import { DeliveryDetailView } from '@/features/deliveries/delivery-detail'

export const Route = createFileRoute('/_app/deliveries/$deliveryId')({
  component: DeliveryPage,
})

function DeliveryPage() {
  const { deliveryId } = Route.useParams()
  return <DeliveryDetailView deliveryId={deliveryId} />
}
