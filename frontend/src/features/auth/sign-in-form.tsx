import { zodResolver } from '@hookform/resolvers/zod'
import { useQueryClient } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { ApiError, apiFetch } from '@/lib/api/client'
import { queryKeys } from '@/lib/api/query-keys'
import type { Me } from '@/lib/api/types'
import { writeKey } from '@/lib/session'
import { safeRedirect } from './session'

const schema = z.object({
  key: z.string().trim().min(1, 'Enter an API key.'),
})

type Values = z.infer<typeof schema>

export function SignInForm({ redirect }: { redirect?: string }) {
  const router = useRouter()
  const queryClient = useQueryClient()
  const [failure, setFailure] = useState<string | null>(null)
  const form = useForm<Values>({ resolver: zodResolver(schema), defaultValues: { key: '' } })

  async function onSubmit({ key }: Values) {
    setFailure(null)
    let me: Me
    try {
      // Checked with the candidate key; only a `200` stores it.
      me = await apiFetch<Me>('/me', { key })
    } catch (error) {
      const rejected = error instanceof ApiError && (error.status === 401 || error.status === 403)
      setFailure(rejected ? 'This key was not accepted.' : 'Courier could not be reached.')
      return
    }
    writeKey(key)
    queryClient.setQueryData(queryKeys.me, me)
    await router.navigate({ href: safeRedirect(redirect) })
  }

  const keyError = form.formState.errors.key

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} noValidate className="max-w-md">
      <FieldGroup>
        {failure && (
          <Alert variant="destructive">
            <AlertDescription>{failure}</AlertDescription>
          </Alert>
        )}
        <Field data-invalid={keyError ? true : undefined}>
          <FieldLabel htmlFor="api-key">API key</FieldLabel>
          <Input
            id="api-key"
            type="password"
            autoComplete="off"
            aria-invalid={keyError ? true : undefined}
            {...form.register('key')}
          />
          <FieldDescription>
            Kept for this browser session only and sent to courier's API.
          </FieldDescription>
          <FieldError errors={[keyError]} />
        </Field>
        <Button type="submit" disabled={form.formState.isSubmitting} className="w-fit">
          Sign in
        </Button>
      </FieldGroup>
    </form>
  )
}
