import { LoaderCircle, Radio } from 'lucide-react'
import type { LiveStatus as Status } from '@/lib/live/transport'

const labels: Record<Status, string> = {
  connecting: 'Connecting…',
  live: 'Live',
  reconnecting: 'Reconnecting…',
}

// Whether the dashboard is receiving change notices.
export function LiveStatus({ status }: { status: Status }) {
  const Icon = status === 'live' ? Radio : LoaderCircle
  return (
    <span role="status" className="flex items-center gap-1.5 text-muted-foreground">
      <Icon
        aria-hidden="true"
        className={status === 'live' ? 'size-4 text-emerald-600' : 'size-4 animate-spin'}
      />
      {labels[status]}
    </span>
  )
}
