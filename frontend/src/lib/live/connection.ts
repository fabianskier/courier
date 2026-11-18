import type { QueryClient } from '@tanstack/react-query'
import { Coalescer, noticeKeys } from './invalidation'
import { createTransport, type LiveStatus } from './transport'

export const liveTopics = [
  'dashboard:events',
  'dashboard:deliveries',
  'dashboard:endpoints',
  'dashboard:merchants',
] as const

export interface LiveConnection {
  stop(): void
}

// The open connection, so sign-out and a `401` can close it from outside React.
let current: LiveConnection | undefined

// Connects with `token`, joins the four topics and refetches what notices
// affect. After a drop, the first `live` refetches every active query once:
// notices missed while down are not replayed.
export function startLive(
  token: string,
  queryClient: QueryClient,
  onStatus: (status: LiveStatus) => void,
): LiveConnection {
  const transport = createTransport(token)
  const coalescer = new Coalescer((keys) => {
    for (const queryKey of keys) {
      void queryClient.invalidateQueries({ queryKey, refetchType: 'active' })
    }
  })
  let status: LiveStatus = 'connecting'
  let stopped = false

  transport.onStatus((next) => {
    if (stopped || next === status) return
    const reconnected = status === 'reconnecting' && next === 'live'
    status = next
    onStatus(next)
    if (reconnected) void queryClient.invalidateQueries({ refetchType: 'active' })
  })
  for (const topic of liveTopics) {
    transport.join(topic, (name, payload) => {
      if (!stopped) coalescer.add(noticeKeys(name, payload))
    })
  }
  transport.connect()

  const connection: LiveConnection = {
    stop() {
      if (stopped) return
      stopped = true
      coalescer.stop()
      transport.disconnect()
      if (current === connection) current = undefined
    },
  }
  current?.stop()
  current = connection
  return connection
}

// Closes the dashboard socket, if one is open.
export function stopLive() {
  current?.stop()
}
