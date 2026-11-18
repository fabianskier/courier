import { Link } from '@tanstack/react-router'
import { NavKey } from '@/components/nav-key'
import { NavMain } from '@/components/nav-main'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
} from '@/components/ui/sidebar'

// shadcn's `sidebar-07` structure: header, the pages, the key at the bottom.
// Collapses to icons.
export function AppSidebar() {
  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton asChild size="lg">
              <Link to="/">
                <span
                  aria-hidden="true"
                  className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary font-heading font-semibold text-sidebar-primary-foreground"
                >
                  C
                </span>
                <span className="font-heading text-base font-semibold">Courier</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <NavMain />
      </SidebarContent>
      <SidebarFooter>
        <NavKey />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}
