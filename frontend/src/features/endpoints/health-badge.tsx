import { CircleCheck, TriangleAlert } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

type Props = { degraded: boolean; consecutiveFailures: number }

const failures = (count: number) => `${count} consecutive ${count === 1 ? 'failure' : 'failures'}`

// An endpoint's health as an icon and text, never by color alone.
export function HealthBadge({ degraded, consecutiveFailures }: Props) {
  const Icon = degraded ? TriangleAlert : CircleCheck
  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <Badge variant={degraded ? 'destructive' : 'success'}>
        <Icon aria-hidden="true" />
        {degraded ? 'Degraded' : 'Healthy'}
      </Badge>
      {consecutiveFailures > 0 && (
        <span className="text-sm text-muted-foreground">{failures(consecutiveFailures)}</span>
      )}
    </span>
  )
}
