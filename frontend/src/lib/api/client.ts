import { readKey } from '@/lib/session'
import type { ApiErrorBody } from './types'

// A failed request: `status` is the HTTP status, or 0 when courier could not be reached.
export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

export interface ApiFetchOptions {
  method?: 'GET' | 'POST'
  query?: Record<string, string | number | undefined>
  signal?: AbortSignal
  // Used instead of the stored key (the sign-in check); its `401` is not reported.
  key?: string
}

let unauthorizedHandler: () => void = () => {}

// Runs `handler` when a request with the stored key answers `401`.
export function onUnauthorized(handler: () => void) {
  unauthorizedHandler = handler
}

export async function apiFetch<T>(path: string, options: ApiFetchOptions = {}): Promise<T> {
  const url = new URL(`/api/v1${path}`, window.location.origin)
  for (const [name, value] of Object.entries(options.query ?? {})) {
    if (value !== undefined && value !== '') url.searchParams.set(name, String(value))
  }
  const key = options.key ?? readKey()
  const headers: Record<string, string> = key ? { Authorization: `Bearer ${key}` } : {}

  let response: Response
  try {
    response = await fetch(url, { method: options.method, headers, signal: options.signal })
  } catch {
    throw new ApiError(0, 'network', 'Courier could not be reached.')
  }
  const body = (await response.json().catch(() => null)) as T & Partial<ApiErrorBody>

  if (response.ok) return body
  if (response.status === 401 && options.key === undefined) unauthorizedHandler()
  const error = body?.error
  throw new ApiError(
    response.status,
    error?.code ?? 'unknown',
    error?.message ?? `Request failed with status ${response.status}.`,
  )
}
