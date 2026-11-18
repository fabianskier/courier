import { useSyncExternalStore } from 'react'

const MOBILE_BREAKPOINT = 768
const QUERY = `(max-width: ${MOBILE_BREAKPOINT - 1}px)`

// Subscribes to the media query instead of copying it into state in an effect
// (shadcn's generated version), so it re-renders only when the match changes.
function subscribe(onChange: () => void) {
  const mql = window.matchMedia(QUERY)
  mql.addEventListener('change', onChange)
  return () => mql.removeEventListener('change', onChange)
}

const isMobileNow = () => window.matchMedia(QUERY).matches

export function useIsMobile() {
  return useSyncExternalStore(subscribe, isMobileNow, () => false)
}
