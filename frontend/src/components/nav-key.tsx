import { useQueryClient } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import { LogOut } from 'lucide-react'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem } from '@/components/ui/sidebar'
import { signOut, useMe } from '@/features/auth/session'

// "ops-reader" → "OR": the avatar of a key, which has a name but no picture.
const initials = (name: string) =>
  name
    .split(/[\s_-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]!.toUpperCase())
    .join('')

// The key in use, its scopes and a visible "Sign out" (not inside a menu).
export function NavKey() {
  const me = useMe()
  const router = useRouter()
  const queryClient = useQueryClient()

  return (
    <SidebarMenu>
      <SidebarMenuItem className="flex items-center gap-2 p-2 group-data-[collapsible=icon]:p-0">
        <Avatar className="size-8 rounded-lg" aria-hidden="true">
          <AvatarFallback className="rounded-lg">{initials(me.name)}</AvatarFallback>
        </Avatar>
        <span
          aria-label="Key in use"
          className="grid min-w-0 flex-1 gap-1 text-sm group-data-[collapsible=icon]:hidden"
        >
          <span className="truncate font-medium">{me.name}</span>
          <span className="flex flex-wrap gap-1">
            {me.scopes.map((scope) => (
              <Badge key={scope} variant="secondary">
                {scope}
              </Badge>
            ))}
          </span>
        </span>
      </SidebarMenuItem>
      <SidebarMenuItem>
        <SidebarMenuButton tooltip="Sign out" onClick={() => void signOut(router, queryClient)}>
          <LogOut aria-hidden="true" />
          <span>Sign out</span>
        </SidebarMenuButton>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
