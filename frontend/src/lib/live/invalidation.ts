import type { QueryKey } from '@tanstack/react-query'
import type { NoticeName, NoticePayload } from './transport'

// The query key prefixes a notice makes stale (see `queryKeys`): lists, the
// changed resource's detail, and the lookups for endpoints and merchants.
export function noticeKeys(name: NoticeName, payload: NoticePayload): QueryKey[] {
  const id = (field: string) => {
    const value = payload[field]
    return typeof value === 'string' ? value : undefined
  }
  const detail = (resource: string, value: string | undefined): QueryKey[] =>
    value ? [[resource, 'detail', value]] : []

  switch (name) {
    case 'event_ingested':
      return [['events', 'list']]
    case 'delivery_changed':
      return [
        ['deliveries', 'list'],
        ...detail('deliveries', id('id')),
        ...detail('events', id('event_id')),
      ]
    case 'endpoint_changed':
      return [['endpoints', 'list'], ['endpoints', 'lookup'], ...detail('endpoints', id('id'))]
    case 'merchant_changed':
      return [['merchants', 'list'], ['merchants', 'lookup'], ...detail('merchants', id('id'))]
    default:
      return []
  }
}

export interface CoalescerOptions {
  // Wait after the first notice of a quiet period, to gather a burst.
  delayMs?: number
  // A prefix is flushed at most once in this window.
  windowMs?: number
}

// Collects query key prefixes and flushes them in batches: the first notice
// flushes after `delayMs`, and a prefix flushed less than `windowMs` ago waits
// until its window ends. A burst therefore costs at most two flushes per
// prefix per second.
export class Coalescer {
  private readonly pending = new Map<string, QueryKey>()
  private readonly lastFlushed = new Map<string, number>()
  private timer: ReturnType<typeof setTimeout> | undefined
  private readonly flush: (keys: QueryKey[]) => void
  private readonly delayMs: number
  private readonly windowMs: number

  constructor(
    flush: (keys: QueryKey[]) => void,
    { delayMs = 250, windowMs = 1_000 }: CoalescerOptions = {},
  ) {
    this.flush = flush
    this.delayMs = delayMs
    this.windowMs = windowMs
  }

  add(keys: QueryKey[]) {
    for (const key of keys) this.pending.set(JSON.stringify(key), key)
    if (this.pending.size > 0 && this.timer === undefined) this.schedule(this.delayMs)
  }

  stop() {
    clearTimeout(this.timer)
    this.timer = undefined
    this.pending.clear()
  }

  private schedule(ms: number) {
    this.timer = setTimeout(() => this.run(), ms)
  }

  private run() {
    this.timer = undefined
    const now = Date.now()
    const ready: QueryKey[] = []
    let nextDue = Infinity
    for (const [id, key] of this.pending) {
      const due = (this.lastFlushed.get(id) ?? -Infinity) + this.windowMs
      if (due <= now) {
        ready.push(key)
        this.pending.delete(id)
        this.lastFlushed.set(id, now)
      } else {
        nextDue = Math.min(nextDue, due)
      }
    }
    if (nextDue !== Infinity) this.schedule(nextDue - now)
    if (ready.length > 0) this.flush(ready)
  }
}
