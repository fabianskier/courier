// Hand-written types of the JSON views the dashboard uses (no OpenAPI yet).

// `GET /api/v1/me` (CourierWeb.MeController).
export interface Me {
  name: string
  scopes: string[]
}

// Every error rendered by CourierWeb.FallbackController.
export interface ApiErrorBody {
  error: { code: string; message: string; details?: Record<string, string[]> }
}

// One page of a cursor-paginated list.
export type Page<T> = { data: T[]; next_cursor: string | null }

// Merchants and endpoints (CourierWeb.MerchantJSON, EndpointJSON): fields used here.
export type Merchant = { id: string; name: string }
// One merchant as `GET /api/v1/merchants[/:id]` renders it.
export interface MerchantDetail extends Merchant {
  enabled: boolean
  inserted_at: string
  updated_at: string
}
export type Endpoint = { id: string; merchant_id: string; url: string }

export type DeliveryStatus = 'pending' | 'succeeded' | 'failed' | 'skipped'

// An item of `GET /api/v1/events` (CourierWeb.EventJSON, without deliveries).
export interface CourierEvent {
  id: string
  type: string
  merchant_id: string
  payload: unknown
  occurred_at: string | null
  received_at: string
}

// `GET /api/v1/events/:id`: the event with its deliveries.
export interface EventDetail extends CourierEvent {
  deliveries: { id: string; endpoint_id: string; status: DeliveryStatus }[]
}

// An item of `GET /api/v1/deliveries` (CourierWeb.DeliveryJSON, without attempts).
export interface DeliverySummary {
  id: string
  event_id: string
  event_type: string | null
  merchant_id: string | null
  endpoint_id: string
  status: DeliveryStatus
  attempt_count: number
  next_attempt_at: string | null
  completed_at: string | null
  resend_of_id: string | null
  triggered_by: string
  inserted_at: string
}

// One attempt of a delivery (request headers are never rendered by the API).
export interface Attempt {
  number: number
  started_at: string
  duration_ms: number | null
  url: string
  response_status: number | null
  response_body: string | null
  error: string | null
}

// `GET /api/v1/deliveries/:id`: the delivery with its resends and attempts.
export interface DeliveryDetail extends DeliverySummary {
  window_ends_at: string | null
  resends: { id: string; status: DeliveryStatus; triggered_by: string; inserted_at: string }[]
  attempts: Attempt[]
}
