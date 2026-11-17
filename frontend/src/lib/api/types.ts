// Hand-written types of the JSON views the dashboard uses (no OpenAPI yet).

// `GET /api/v1/me` (CourierWeb.MeController).
export interface Me {
  name: string
  scopes: string[]
}

// Every error rendered by CourierWeb.FallbackController.
export interface ApiErrorBody {
  error: { code: string; message: string }
}

// One page of a cursor-paginated list.
export type Page<T> = { data: T[]; next_cursor: string | null }

// Merchants and endpoints (CourierWeb.MerchantJSON, EndpointJSON): fields used here.
export type Merchant = { id: string; name: string }
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
