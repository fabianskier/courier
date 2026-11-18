import { MerchantSwitcher } from '@/components/merchant-switcher'
import { NavKey } from '@/components/nav-key'
import { NavMain } from '@/components/nav-main'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from '@/components/ui/sidebar'

// shadcn's `sidebar-07` structure: the merchant switcher, the pages, the key
// at the bottom. Collapses to icons.
export function AppSidebar() {
  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <MerchantSwitcher />
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
