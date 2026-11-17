import { readKey } from '@/lib/session'
import type { ApiErrorBody } from './types'

const BASE_PATH = '/api/v1'

// A failed request: `status` is the HTTP status, or 0 when courier could not
// be reached at all.
export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

type QueryValue = string | number | boolean | null | undefined

export interface ApiFetchOptions {
  method?: 'GET' | 'POST'
  query?: Record<string, QueryValue>
  signal?: AbortSignal
  // A key to use instead of the stored one (the sign-in check). A `401` for an
  // explicit key does not trigger the unauthorized handler.
  key?: string
}

let unauthorizedHandler: (() => void) | null = null

// Registers the handler run when a request with the stored key answers `401`.
// Returns a function that removes it.
export function onUnauthorized(handler: () => void) {
  unauthorizedHandler = handler
  return () => {
    if (unauthorizedHandler === handler) unauthorizedHandler = null
  }
}

export async function apiFetch<T>(path: string, options: ApiFetchOptions = {}): Promise<T> {
  const url = new URL(BASE_PATH + path, window.location.origin)
  for (const [name, value] of Object.entries(options.query ?? {})) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(name, String(value))
    }
  }

  const key = options.key ?? readKey()
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (key) headers.Authorization = `Bearer ${key}`

  const { method = 'GET', signal } = options
  let response: Response
  try {
    response = await fetch(url, { method, headers, signal })
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error
    throw new ApiError(0, 'network', 'Courier could not be reached.')
  }

  const body: unknown = await response.json().catch(() => null)

  if (!response.ok) {
    if (response.status === 401 && options.key === undefined) unauthorizedHandler?.()
    throw toApiError(response.status, body)
  }

  return body as T
}

function toApiError(status: number, body: unknown): ApiError {
  const error = (body as Partial<ApiErrorBody> | null)?.error
  if (typeof error?.code === 'string' && typeof error.message === 'string') {
    return new ApiError(status, error.code, error.message)
  }
  return new ApiError(status, 'unknown', `Request failed with status ${status}.`)
}
