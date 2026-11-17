import { Badge } from '@/components/ui/badge'

// A merchant's state as text, not color alone.
export function MerchantState({ enabled }: { enabled: boolean }) {
  return (
    <Badge variant={enabled ? 'secondary' : 'outline'}>{enabled ? 'Enabled' : 'Disabled'}</Badge>
  )
}
