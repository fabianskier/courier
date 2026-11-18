import { createFileRoute, Outlet, redirect, useLocation } from '@tanstack/react-router'
import { AppShell } from '@/components/app-shell'
import { ensureMe } from '@/features/auth/session'
import { readKey } from '@/lib/session'

// Every page with courier data: needs a stored key that `/me` accepts.
export const Route = createFileRoute('/_app')({
  beforeLoad: async ({ context, location }) => {
    if (!readKey()) throw redirect({ to: '/sign-in', search: { redirect: location.href } })
    await ensureMe(context.queryClient, location.href)
  },
  component: AppLayout,
})

// The breadcrumb's page, from the path's first segment: detail pages name
// their list.
const titles: Record<string, string> = {
  events: 'Events',
  deliveries: 'Deliveries',
  failed: 'Failed',
  endpoints: 'Endpoints',
  merchants: 'Merchants',
}

function AppLayout() {
  const title = useLocation({ select: (location) => titles[location.pathname.split('/')[1] ?? ''] })

  return (
    <AppShell title={title ?? 'Overview'}>
      <Outlet />
    </AppShell>
  )
}
