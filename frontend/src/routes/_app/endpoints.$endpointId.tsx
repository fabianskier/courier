import { createFileRoute } from '@tanstack/react-router'
import { EndpointDetailView } from '@/features/endpoints/endpoint-detail'

export const Route = createFileRoute('/_app/endpoints/$endpointId')({
  component: EndpointPage,
})

function EndpointPage() {
  const { endpointId } = Route.useParams()
  return <EndpointDetailView endpointId={endpointId} />
}
