import { useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { readKey } from '@/lib/session'
import { startLive } from './connection'
import type { LiveStatus } from './transport'

// Keeps the signed-in pages current from change notices while mounted, and
// returns whether updates are live.
export function useLiveUpdates(): LiveStatus {
  const queryClient = useQueryClient()
  const [status, setStatus] = useState<LiveStatus>('connecting')

  useEffect(() => {
    const token = readKey()
    if (!token) return
    const connection = startLive(token, queryClient, setStatus)
    return () => connection.stop()
  }, [queryClient])

  return status
}
