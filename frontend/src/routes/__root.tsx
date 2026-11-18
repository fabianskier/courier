import { createRootRouteWithContext, Link, Outlet, useMatches } from '@tanstack/react-router'
import { ModeToggle } from '@/components/mode-toggle'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { readKey } from '@/lib/session'
import type { RouterContext } from '@/router'

export const Route = createRootRouteWithContext<RouterContext>()({
  component: RootLayout,
  notFoundComponent: NotFound,
})

// Signed-in pages (`_app`, and the overview with a key) render `AppShell`,
// which brings its own header and `main`: this header is then left out.
const showsShell = (matches: { routeId: string }[]) =>
  matches.some(
    (match) => match.routeId === '/_app' || (match.routeId === '/' && Boolean(readKey())),
  )

function RootLayout() {
  const shell = useMatches({ select: showsShell })

  return (
    <TooltipProvider>
      <div className="min-h-svh bg-background text-foreground">
        {shell ? (
          <Outlet />
        ) : (
          <>
            <header className="border-b">
              <nav
                aria-label="Main"
                className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-3"
              >
                <Link to="/" className="font-heading text-lg font-semibold">
                  Courier
                </Link>
                <div className="ml-auto">
                  <ModeToggle />
                </div>
              </nav>
            </header>
            <main className="mx-auto max-w-6xl px-6 py-8">
              <Outlet />
            </main>
          </>
        )}
      </div>
      <Toaster />
    </TooltipProvider>
  )
}

function NotFound() {
  return (
    <section>
      <h1 className="font-heading text-2xl font-semibold">Page not found</h1>
      <p className="mt-2 text-muted-foreground">
        <Link to="/" className="underline underline-offset-4">
          Back to the overview
        </Link>
      </p>
    </section>
  )
}
