import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/')({
  component: Overview,
})

// Placeholder until the dashboard changes (deliveries, endpoints) add pages.
function Overview() {
  return (
    <section>
      <h1 className="font-heading text-2xl font-semibold">Overview</h1>
      <p className="mt-2 text-muted-foreground">
        The webhook delivery dashboard. Deliveries and endpoints come next.
      </p>
    </section>
  )
}
