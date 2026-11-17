import { createFileRoute, Link } from '@tanstack/react-router'
import { hasKey } from '@/lib/session'

export const Route = createFileRoute('/')({
  component: Overview,
})

// Open without a key, and sends no request: the data pages live under `_app`.
function Overview() {
  const signedIn = hasKey()

  return (
    <section>
      <h1 className="font-heading text-2xl font-semibold">Overview</h1>
      <p className="mt-2 text-muted-foreground">The webhook delivery dashboard.</p>
      <p className="mt-4">
        {signedIn ? (
          <Link to="/deliveries" className="underline underline-offset-4">
            Open deliveries
          </Link>
        ) : (
          <Link to="/sign-in" className="underline underline-offset-4">
            Sign in
          </Link>
        )}
      </p>
    </section>
  )
}
