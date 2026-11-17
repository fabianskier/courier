// The API key lives in session storage only (API keys ADR): never in local
// storage, cookies, the URL or logs.
const STORAGE_KEY = 'courier.apiKey'

export const readKey = () => window.sessionStorage.getItem(STORAGE_KEY)
export const writeKey = (key: string) => window.sessionStorage.setItem(STORAGE_KEY, key)
export const clearKey = () => window.sessionStorage.removeItem(STORAGE_KEY)
