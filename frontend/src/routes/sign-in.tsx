import { createFileRoute } from '@tanstack/react-router'
import { z } from 'zod'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { SignInForm } from '@/features/auth/sign-in-form'

const searchSchema = z.object({
  redirect: z.string().optional().catch(undefined),
  reason: z.literal('expired').optional().catch(undefined),
})

export const Route = createFileRoute('/sign-in')({
  validateSearch: searchSchema,
  component: SignIn,
})

function SignIn() {
  const { redirect, reason } = Route.useSearch()

  return (
    <section className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-2xl font-semibold">Sign in</h1>
        <p className="mt-2 text-muted-foreground">Enter an API key to open the dashboard.</p>
      </div>
      {reason === 'expired' && (
        <Alert className="max-w-md">
          <AlertDescription>
            Your key is no longer accepted. Sign in with another key.
          </AlertDescription>
        </Alert>
      )}
      <SignInForm redirect={redirect} />
    </section>
  )
}
