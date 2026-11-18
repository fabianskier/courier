import { ThemeProvider as NextThemesProvider } from 'next-themes'
import type { ReactNode } from 'react'

// Where the operator's mode choice is kept. The head script in `index.html`
// reads the same key to set the mode before the first paint.
export const THEME_STORAGE_KEY = 'courier.theme'

// Light, dark or the operating system's preference (the default), applied as
// the `dark` class on `<html>`.
export function ThemeProvider({ children }: { children: ReactNode }) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      storageKey={THEME_STORAGE_KEY}
      disableTransitionOnChange
    >
      {children}
    </NextThemesProvider>
  )
}
