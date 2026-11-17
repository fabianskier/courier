import { useQueryClient } from '@tanstack/react-query'
import { createFileRoute, Link, Outlet, redirect, useRouter } from '@tanstack/react-router'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { meQueryOptions, signOut, useMe } from '@/features/auth/session'
import { ApiError } from '@/lib/api/client'
import { readKey } from '@/lib/session'

// Every page with courier data: needs a stored key that `/me` accepts.
export const Route = createFileRoute('/_app')({
  beforeLoad: async ({ context, location }) => {
    const search = { redirect: location.href }
    if (!readKey()) throw redirect({ to: '/sign-in', search })
    await context.queryClient.ensureQueryData(meQueryOptions()).catch((error: unknown) => {
      if (!(error instanceof ApiError) || error.status !== 401) throw error
      throw redirect({ to: '/sign-in', search: { ...search, reason: 'expired' } })
    })
  },
  component: AppLayout,
})

// Failed joins when its page exists (task 3.2).
const links = [
  { to: '/', label: 'Overview' },
  { to: '/events', label: 'Events' },
  { to: '/deliveries', label: 'Deliveries' },
] as const

function AppLayout() {
  const me = useMe()
  const router = useRouter()
  const queryClient = useQueryClient()

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b pb-4">
        <nav aria-label="Dashboard" className="flex gap-4 text-sm">
          {links.map((link) => (
            <Link
              key={link.to}
              to={link.to}
              activeOptions={{ exact: link.to === '/' }}
              className="text-muted-foreground hover:text-foreground data-[status=active]:font-medium data-[status=active]:text-foreground"
            >
              {link.label}
            </Link>
          ))}
        </nav>
        <div className="flex items-center gap-3 text-sm">
          <span aria-label="Key in use" className="flex items-center gap-2">
            <span className="font-medium">{me.name}</span>
            {me.scopes.map((scope) => (
              <Badge key={scope} variant="secondary">
                {scope}
              </Badge>
            ))}
          </span>
          <Button variant="outline" size="sm" onClick={() => void signOut(router, queryClient)}>
            Sign out
          </Button>
        </div>
      </div>
      <Outlet />
    </div>
  )
}
