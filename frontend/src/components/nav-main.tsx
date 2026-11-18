import { Link } from '@tanstack/react-router'
import { ChevronRight, CircleX, Inbox, LayoutDashboard, Send, Store, Webhook } from 'lucide-react'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar'
import { isMerchantList, useSelectedMerchant } from '@/lib/merchant-context'

type Page = {
  to: '/' | '/events' | '/deliveries' | '/failed' | '/endpoints' | '/merchants'
  label: string
  icon: typeof LayoutDashboard
}

const overview: Page = { to: '/', label: 'Overview', icon: LayoutDashboard }

const groups: { label: string; pages: Page[] }[] = [
  {
    label: 'Activity',
    pages: [
      { to: '/events', label: 'Events', icon: Inbox },
      { to: '/deliveries', label: 'Deliveries', icon: Send },
      { to: '/failed', label: 'Failed', icon: CircleX },
    ],
  },
  {
    label: 'Configuration',
    pages: [
      { to: '/endpoints', label: 'Endpoints', icon: Webhook },
      { to: '/merchants', label: 'Merchants', icon: Store },
    ],
  },
]

// One page link; the router marks the current one (`aria-current="page"`),
// detail pages included under their list.
// The four lists carry the switcher's merchant as their `merchant_id` filter.
function PageItem({ page }: { page: Page }) {
  const Icon = page.icon
  const merchantId = useSelectedMerchant()
  const search = isMerchantList(page.to) && merchantId ? { merchant_id: merchantId } : {}
  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        asChild
        tooltip={page.label}
        className="data-[status=active]:bg-sidebar-accent data-[status=active]:font-medium data-[status=active]:text-sidebar-accent-foreground"
      >
        <Link
          to={page.to}
          search={search}
          activeOptions={{ exact: page.to === '/', includeSearch: false }}
        >
          <Icon aria-hidden="true" />
          <span>{page.label}</span>
        </Link>
      </SidebarMenuButton>
    </SidebarMenuItem>
  )
}

// The dashboard's pages: Overview, then the two groups, each collapsible and
// open by default.
export function NavMain() {
  return (
    <nav aria-label="Dashboard">
      <SidebarGroup>
        <SidebarMenu>
          <PageItem page={overview} />
        </SidebarMenu>
      </SidebarGroup>
      {groups.map((group) => (
        <Collapsible key={group.label} defaultOpen className="group/collapsible">
          <SidebarGroup>
            <SidebarGroupLabel asChild>
              <CollapsibleTrigger>
                {group.label}
                <ChevronRight
                  aria-hidden="true"
                  className="ml-auto transition-transform group-data-[state=open]/collapsible:rotate-90"
                />
              </CollapsibleTrigger>
            </SidebarGroupLabel>
            <CollapsibleContent>
              <SidebarGroupContent>
                <SidebarMenu aria-label={group.label}>
                  {group.pages.map((page) => (
                    <PageItem key={page.to} page={page} />
                  ))}
                </SidebarMenu>
              </SidebarGroupContent>
            </CollapsibleContent>
          </SidebarGroup>
        </Collapsible>
      ))}
    </nav>
  )
}
