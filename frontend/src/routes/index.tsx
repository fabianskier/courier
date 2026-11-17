import { createFileRoute, Link } from '@tanstack/react-router'
import { readKey } from '@/lib/session'

export const Route = createFileRoute('/')({
  component: Overview,
})

// Open without a key, and sends no request: the data pages live under `_app`.
function Overview() {
  return (
    <section>
      <h1 className="font-heading text-2xl font-semibold">Overview</h1>
      <p className="mt-2 text-muted-foreground">The webhook delivery dashboard.</p>
      {!readKey() && (
        <Link to="/sign-in" className="mt-4 inline-block underline underline-offset-4">
          Sign in
        </Link>
      )}
    </section>
  )
}
