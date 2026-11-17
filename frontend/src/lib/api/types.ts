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

// Paginated lists: `{"data": [...], "next_cursor": ...}`.
export interface Page<T> {
  data: T[]
  next_cursor: string | null
}
