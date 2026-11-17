// Times come from the API in UTC and are shown in the operator's locale and
// time zone; `datetime-local` inputs hold local time and go back as UTC ISO.

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'medium' })

export function formatDateTime(iso: string | null | undefined) {
  return iso ? dateTime.format(new Date(iso)) : '—'
}

// `2026-11-01T09:00:00Z` -> `2026-11-01T10:00` in UTC+1, for a datetime-local input.
export function toLocalInput(iso: string | undefined) {
  if (!iso) return ''
  const date = new Date(iso)
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
}

// A datetime-local value (local time) -> UTC ISO, or undefined when empty or invalid.
export function fromLocalInput(value: string) {
  const date = new Date(value)
  return value && !Number.isNaN(date.getTime()) ? date.toISOString() : undefined
}

// A retry window in seconds: 86,400 -> "24 hours", 5,400 -> "1.5 hours", 60 -> "1 minute".
export function formatRetryWindow(seconds: number) {
  if (seconds < 3600) {
    const minutes = Math.round((seconds / 60) * 100) / 100
    return `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`
  }
  const hours = Math.round((seconds / 3600) * 100) / 100
  return `${hours} ${hours === 1 ? 'hour' : 'hours'}`
}

// An id that could not be named: its first eight characters.
export const shortId = (id: string) => id.slice(0, 8)
