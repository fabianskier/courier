import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from '@tanstack/react-router'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { ThemeProvider } from '@/components/theme-provider'
import { installUnauthorizedHandler } from '@/features/auth/session'
import { createAppQueryClient, createAppRouter } from '@/router'
import './index.css'

const queryClient = createAppQueryClient()
const router = createAppRouter(queryClient)
// Any `401` for the stored key sends the operator back to sign-in.
installUnauthorizedHandler(router, queryClient)

const root = document.getElementById('root')
if (!root) throw new Error('missing #root element in index.html')

createRoot(root).render(
  <StrictMode>
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </ThemeProvider>
  </StrictMode>,
)
