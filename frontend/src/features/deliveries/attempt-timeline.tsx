import { useState } from 'react'
import { Button } from '@/components/ui/button'
import type { Attempt } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'

// Longer response bodies are cut here until the operator asks for the rest.
export const BODY_PREVIEW = 500

// A delivery's attempts in order: number, start, duration, status or error, body.
export function AttemptTimeline({ attempts }: { attempts: Attempt[] }) {
  if (attempts.length === 0) return <p className="text-muted-foreground">No attempts yet.</p>

  return (
    <ol aria-label="Attempts" className="flex flex-col gap-4 border-l pl-4">
      {attempts.map((attempt) => (
        <li key={attempt.number} className="flex flex-col gap-1 text-sm">
          <h3 className="font-medium">Attempt {attempt.number}</h3>
          <p className="text-muted-foreground">
            {formatDateTime(attempt.started_at)}
            {attempt.duration_ms !== null && ` · ${attempt.duration_ms} ms`}
          </p>
          {attempt.response_status !== null ? (
            <p>
              Status code <span className="font-mono">{attempt.response_status}</span>
            </p>
          ) : (
            <p>
              Error <span className="font-mono">{attempt.error ?? 'unknown'}</span>
            </p>
          )}
          {attempt.response_body && <ResponseBody body={attempt.response_body} />}
        </li>
      ))}
    </ol>
  )
}

// The response body as text, shortened with "Show more" when long.
function ResponseBody({ body }: { body: string }) {
  const [expanded, setExpanded] = useState(false)
  const long = body.length > BODY_PREVIEW
  const shown = long && !expanded ? `${body.slice(0, BODY_PREVIEW)}…` : body

  return (
    <div className="flex flex-col items-start gap-1">
      <pre
        aria-label="Response body"
        className="max-w-full overflow-x-auto rounded-lg bg-muted p-3 whitespace-pre-wrap"
      >
        {shown}
      </pre>
      {long && (
        <Button variant="link" size="sm" onClick={() => setExpanded(!expanded)}>
          {expanded ? 'Show less' : 'Show more'}
        </Button>
      )}
    </div>
  )
}
