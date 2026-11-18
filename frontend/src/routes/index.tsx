import { createFileRoute, Link } from '@tanstack/react-router'
import { readKey } from '@/lib/session'

export const Route = createFileRoute('/')({
  component: Overview,
})

// The dashboard's pages, offered here because the overview sits outside the
// `_app` layout and its navigation.
const pages = [
  { to: '/events', label: 'Events', text: 'What producers sent, newest first.' },
  { to: '/deliveries', label: 'Deliveries', text: 'Every delivery to an endpoint.' },
  { to: '/failed', label: 'Failed', text: 'Deliveries that failed for good, to resend.' },
  { to: '/endpoints', label: 'Endpoints', text: 'Merchant endpoints and their health.' },
  { to: '/merchants', label: 'Merchants', text: 'Merchants and their endpoints.' },
] as const

// Open without a key, and sends no request: the data pages live under `_app`.
function Overview() {
  const signedIn = Boolean(readKey())

  return (
    <section>
      <h1 className="font-heading text-2xl font-semibold">Overview</h1>
      <p className="mt-2 text-muted-foreground">The webhook delivery dashboard.</p>
      {signedIn ? (
        <ul aria-label="Dashboard pages" className="mt-6 grid gap-3 sm:grid-cols-2">
          {pages.map((page) => (
            <li key={page.to}>
              <Link
                to={page.to}
                className="block rounded-lg border p-4 hover:bg-muted focus-visible:outline-2"
              >
                <span className="font-medium">{page.label}</span>
                <span className="mt-1 block text-sm text-muted-foreground">{page.text}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <Link to="/sign-in" className="mt-4 inline-block underline underline-offset-4">
          Sign in
        </Link>
      )}
    </section>
  )
}
