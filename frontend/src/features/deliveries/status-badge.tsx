import { CircleCheck, CircleMinus, CircleX, Clock, type LucideIcon } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import type { DeliveryStatus } from '@/lib/api/types'

const looks: Record<DeliveryStatus, { icon: LucideIcon; variant: 'outline' | 'destructive' }> = {
  pending: { icon: Clock, variant: 'outline' },
  succeeded: { icon: CircleCheck, variant: 'outline' },
  failed: { icon: CircleX, variant: 'destructive' },
  skipped: { icon: CircleMinus, variant: 'outline' },
}

// A delivery's status as an icon and text, never by color alone.
export function StatusBadge({ status }: { status: DeliveryStatus }) {
  const { icon: Icon, variant } = looks[status]
  return (
    <Badge variant={variant}>
      <Icon aria-hidden="true" />
      {status}
    </Badge>
  )
}
