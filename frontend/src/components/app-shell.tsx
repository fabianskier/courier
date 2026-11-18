import { Link } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { AppSidebar } from '@/components/app-sidebar'
import { LiveStatus } from '@/components/live-status'
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from '@/components/ui/breadcrumb'
import { Separator } from '@/components/ui/separator'
import { SidebarInset, SidebarProvider, SidebarTrigger } from '@/components/ui/sidebar'
import { useLiveUpdates } from '@/lib/live/use-live-updates'

// The signed-in layout: the sidebar, and a header with its toggle, the
// breadcrumb of `title` and the live status. Needs `/me` loaded.
export function AppShell({ title, children }: { title: string; children: ReactNode }) {
  const liveStatus = useLiveUpdates()

  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <header className="flex h-14 shrink-0 items-center gap-2 border-b px-4">
          <SidebarTrigger aria-label="Toggle sidebar" className="-ml-1" />
          <Separator orientation="vertical" className="mr-2 data-[orientation=vertical]:h-4" />
          <Breadcrumb>
            <BreadcrumbList>
              <BreadcrumbItem className="hidden md:block">
                <BreadcrumbLink asChild>
                  <Link to="/">Dashboard</Link>
                </BreadcrumbLink>
              </BreadcrumbItem>
              <BreadcrumbSeparator className="hidden md:block" />
              <BreadcrumbItem>
                <BreadcrumbPage>{title}</BreadcrumbPage>
              </BreadcrumbItem>
            </BreadcrumbList>
          </Breadcrumb>
          <div className="ml-auto text-sm">
            <LiveStatus status={liveStatus} />
          </div>
        </header>
        <div className="flex flex-1 flex-col gap-8 p-6">{children}</div>
      </SidebarInset>
    </SidebarProvider>
  )
}
