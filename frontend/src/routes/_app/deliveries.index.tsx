import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_app/deliveries/')({
  component: Deliveries,
})

// Placeholder: the deliveries list comes with task 3.2 of add-dashboard-deliveries.
function Deliveries() {
  return <h1 className="font-heading text-2xl font-semibold">Deliveries</h1>
}
