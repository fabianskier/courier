// The API key lives in session storage only (API keys ADR): never in local
// storage, cookies, the URL or logs.
const STORAGE_KEY = 'courier.apiKey'

export function readKey(): string | null {
  return window.sessionStorage.getItem(STORAGE_KEY)
}

export function writeKey(key: string) {
  window.sessionStorage.setItem(STORAGE_KEY, key)
}

export function clearKey() {
  window.sessionStorage.removeItem(STORAGE_KEY)
}

export function hasKey(): boolean {
  return readKey() !== null
}
