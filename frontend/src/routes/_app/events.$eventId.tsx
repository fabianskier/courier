import { createFileRoute } from '@tanstack/react-router'
import { EventDetailView } from '@/features/events/event-detail'

export const Route = createFileRoute('/_app/events/$eventId')({
  component: EventPage,
})

function EventPage() {
  const { eventId } = Route.useParams()
  return <EventDetailView eventId={eventId} />
}
