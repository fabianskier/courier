import { useSyncExternalStore } from 'react'

// The merchant the switcher focuses the lists on, kept for the browser session.
// A view filter only: it grants or restricts nothing. The id is not a secret.
const STORAGE_KEY = 'courier.merchant'

const listeners = new Set<() => void>()

const read = () => window.sessionStorage.getItem(STORAGE_KEY) ?? undefined

// Selects a merchant, or all merchants with `undefined`.
export function setSelectedMerchant(id: string | undefined) {
  if (id) window.sessionStorage.setItem(STORAGE_KEY, id)
  else window.sessionStorage.removeItem(STORAGE_KEY)
  listeners.forEach((listener) => listener())
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

// The selected merchant's id, or `undefined` for all merchants.
export const useSelectedMerchant = () => useSyncExternalStore(subscribe, read, read)

// The lists whose `merchant_id` filter follows the selection.
export const merchantLists = ['/events', '/deliveries', '/failed', '/endpoints'] as const

export type MerchantList = (typeof merchantLists)[number]

export const isMerchantList = (path: string): path is MerchantList =>
  (merchantLists as readonly string[]).includes(path.replace(/\/$/, ''))
