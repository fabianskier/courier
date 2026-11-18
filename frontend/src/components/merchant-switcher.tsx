import { useLocation, useNavigate } from '@tanstack/react-router'
import { ChevronsUpDown, Store } from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar'
import { useMerchants } from '@/lib/api/lookups'
import { shortId } from '@/lib/format'
import { isMerchantList, setSelectedMerchant, useSelectedMerchant } from '@/lib/merchant-context'

const ALL = 'all'

// The sidebar's top switcher (shadcn block: `team-switcher`): focuses the
// lists on one merchant. It only filters views; the key still sees everything.
export function MerchantSwitcher() {
  const merchants = useMerchants()
  const selected = useSelectedMerchant()
  const { isMobile } = useSidebar()
  const navigate = useNavigate()
  const pathname = useLocation({ select: (location) => location.pathname })

  const name = selected
    ? (merchants.find((m) => m.id === selected)?.name ?? shortId(selected))
    : 'All merchants'

  const choose = (value: string) => {
    const merchantId = value === ALL ? undefined : value
    setSelectedMerchant(merchantId)
    if (isMerchantList(pathname)) {
      // The current list follows the selection, keeping its other filters.
      void navigate({
        to: '.',
        search: (prev) => ({ ...prev, merchant_id: merchantId }),
      })
    }
  }

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <SidebarMenuButton
              size="lg"
              aria-label={`Viewing ${name}`}
              className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
            >
              <span
                aria-hidden="true"
                className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground"
              >
                <Store className="size-4" />
              </span>
              <span className="grid flex-1 text-left text-sm leading-tight">
                <span className="truncate text-xs text-muted-foreground">Viewing</span>
                <span className="truncate font-medium">{name}</span>
              </span>
              <ChevronsUpDown aria-hidden="true" className="ml-auto" />
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg"
            align="start"
            side={isMobile ? 'bottom' : 'right'}
            sideOffset={4}
          >
            <DropdownMenuLabel className="text-xs text-muted-foreground">
              Merchants
            </DropdownMenuLabel>
            <DropdownMenuRadioGroup value={selected ?? ALL} onValueChange={choose}>
              <DropdownMenuRadioItem value={ALL}>All merchants</DropdownMenuRadioItem>
              {merchants.length > 0 && <DropdownMenuSeparator />}
              {merchants.map((merchant) => (
                <DropdownMenuRadioItem key={merchant.id} value={merchant.id}>
                  {merchant.name}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
