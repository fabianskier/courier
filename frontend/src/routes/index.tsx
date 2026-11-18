import { createFileRoute, Link } from '@tanstack/react-router'
import { AppShell } from '@/components/app-shell'
import { ensureMe } from '@/features/auth/session'
import { readKey } from '@/lib/session'

// Open without a key, and then sends no request. With a key it loads `/me`
// like `_app`, for the shell.
export const Route = createFileRoute('/')({
  beforeLoad: async ({ context, location }) => {
    if (readKey()) await ensureMe(context.queryClient, location.href)
  },
  component: Overview,
})

// The dashboard's pages, also in the sidebar, offered here as a starting point.
const pages = [
  { to: '/events', label: 'Events', text: 'What producers sent, newest first.' },
  { to: '/deliveries', label: 'Deliveries', text: 'Every delivery to an endpoint.' },
  { to: '/failed', label: 'Failed', text: 'Deliveries that failed for good, to resend.' },
  { to: '/endpoints', label: 'Endpoints', text: 'Merchant endpoints and their health.' },
  { to: '/merchants', label: 'Merchants', text: 'Merchants and their endpoints.' },
] as const

function Overview() {
  const signedIn = Boolean(readKey())
  const content = <OverviewContent signedIn={signedIn} />

  return signedIn ? <AppShell title="Overview">{content}</AppShell> : content
}

function OverviewContent({ signedIn }: { signedIn: boolean }) {
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
