import { CircleCheck, CircleMinus, CircleX, Clock, type LucideIcon } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import type { DeliveryStatus } from '@/lib/api/types'

type Variant = 'success' | 'destructive' | 'warning' | 'secondary'

const looks: Record<DeliveryStatus, { icon: LucideIcon; variant: Variant }> = {
  pending: { icon: Clock, variant: 'warning' },
  succeeded: { icon: CircleCheck, variant: 'success' },
  failed: { icon: CircleX, variant: 'destructive' },
  skipped: { icon: CircleMinus, variant: 'secondary' },
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
