import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { z } from 'zod'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import * as S from '@/components/ui/select'
import { useMerchants } from '@/lib/api/lookups'
import { queryKeys } from '@/lib/api/query-keys'
import type { EndpointDetail } from '@/lib/api/types'
import { applyApiErrors } from '@/lib/forms'
import { createEndpoint, splitEventTypes, toEndpointFormError } from './queries'
import { SecretReveal } from './secret-reveal'

// Only required fields and number types are checked here: the API's
// messages (unsafe URL, retry window range, ...) are shown on their fields.
const schema = z.object({
  merchant_id: z.string().min(1, 'Choose a merchant.'),
  url: z.string().trim().min(1, 'Enter a URL.'),
  description: z.string(),
  event_types: z.string(),
  retry_window_hours: z.number('Enter a number of hours.'),
  retry_on_4xx: z.boolean(),
  max_concurrency: z.number('Enter a number.').int('Enter a whole number.').min(1).max(50),
})

type Values = z.infer<typeof schema>

// Creates an endpoint, then shows its signing secret once in place of the form.
export function NewEndpointForm({ merchantId }: { merchantId?: string }) {
  const merchants = useMerchants()
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const [failure, setFailure] = useState<string | null>(null)
  // The secret and the endpoint it signs for: component state only.
  const [created, setCreated] = useState<{ endpoint: EndpointDetail; secret: string } | null>(null)

  const form = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: {
      merchant_id: merchantId ?? '',
      url: '',
      description: '',
      event_types: '',
      retry_window_hours: 24,
      retry_on_4xx: false,
      max_concurrency: 10,
    },
  })

  const mutation = useMutation({
    // Returns the endpoint without its secret, so the mutation cache never holds it.
    mutationFn: async (values: Values) => {
      const description = values.description.trim()
      const { endpoint, secret } = await createEndpoint({
        merchant_id: values.merchant_id,
        url: values.url.trim(),
        ...(description && { description }),
        event_types: splitEventTypes(values.event_types),
        retry_window_seconds: Math.round(values.retry_window_hours * 3600),
        retry_on_4xx: values.retry_on_4xx,
        max_concurrency: values.max_concurrency,
      })
      setCreated({ endpoint, secret })
      return endpoint
    },
    onSuccess: async (endpoint) => {
      queryClient.setQueryData(queryKeys.endpoint(endpoint.id), { data: endpoint })
      // Lists and lookups pick up the new endpoint.
      await queryClient.invalidateQueries({ queryKey: ['endpoints'] })
    },
    onError: (error) => setFailure(applyApiErrors(form, toEndpointFormError(error))),
  })

  const onSubmit = (values: Values) => {
    setFailure(null)
    return mutation.mutateAsync(values).catch(() => {})
  }

  if (created) {
    const { endpoint, secret } = created
    return (
      <div className="flex max-w-xl flex-col gap-6">
        <p>
          Endpoint created for <span className="font-mono break-all">{endpoint.url}</span>.
        </p>
        <SecretReveal secret={secret} />
        <Button
          className="w-fit"
          onClick={() =>
            void navigate({ to: '/endpoints/$endpointId', params: { endpointId: endpoint.id } })
          }
        >
          Continue to the endpoint
        </Button>
      </div>
    )
  }

  const { errors } = form.formState
  const invalid = (name: keyof Values) => (errors[name] ? true : undefined)

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} noValidate className="max-w-xl">
      <FieldGroup>
        {failure && (
          <Alert variant="destructive">
            <AlertDescription>{failure}</AlertDescription>
          </Alert>
        )}
        <Field data-invalid={invalid('merchant_id')}>
          <FieldLabel htmlFor="endpoint-merchant">Merchant</FieldLabel>
          <Controller
            control={form.control}
            name="merchant_id"
            render={({ field }) => (
              <S.Select value={field.value} onValueChange={field.onChange}>
                <S.SelectTrigger
                  id="endpoint-merchant"
                  className="w-full"
                  aria-invalid={invalid('merchant_id')}
                >
                  <S.SelectValue placeholder="Choose a merchant" />
                </S.SelectTrigger>
                <S.SelectContent>
                  {merchants.map((m) => (
                    <S.SelectItem key={m.id} value={m.id}>
                      {m.name}
                    </S.SelectItem>
                  ))}
                </S.SelectContent>
              </S.Select>
            )}
          />
          <FieldError errors={[errors.merchant_id]} />
        </Field>
        <Field data-invalid={invalid('url')}>
          <FieldLabel htmlFor="endpoint-url">URL</FieldLabel>
          <Input
            id="endpoint-url"
            type="url"
            autoComplete="off"
            placeholder="https://example.com/webhooks"
            aria-invalid={invalid('url')}
            {...form.register('url')}
          />
          <FieldError errors={[errors.url]} />
        </Field>
        <Field data-invalid={invalid('description')}>
          <FieldLabel htmlFor="endpoint-description">Description</FieldLabel>
          <Input
            id="endpoint-description"
            autoComplete="off"
            aria-invalid={invalid('description')}
            {...form.register('description')}
          />
          <FieldError errors={[errors.description]} />
        </Field>
        <Field data-invalid={invalid('event_types')}>
          <FieldLabel htmlFor="endpoint-event-types">Event types</FieldLabel>
          <Input
            id="endpoint-event-types"
            autoComplete="off"
            placeholder="payment.*, refund.created"
            aria-invalid={invalid('event_types')}
            {...form.register('event_types')}
          />
          <FieldDescription>Comma-separated. Leave empty for all event types.</FieldDescription>
          <FieldError errors={[errors.event_types]} />
        </Field>
        <Field data-invalid={invalid('retry_window_hours')}>
          <FieldLabel htmlFor="endpoint-retry-window">Retry window (hours)</FieldLabel>
          <Input
            id="endpoint-retry-window"
            type="number"
            min={0}
            max={24}
            step={0.01}
            aria-invalid={invalid('retry_window_hours')}
            {...form.register('retry_window_hours', { valueAsNumber: true })}
          />
          <FieldError errors={[errors.retry_window_hours]} />
        </Field>
        <Field data-invalid={invalid('max_concurrency')}>
          <FieldLabel htmlFor="endpoint-concurrency">Concurrency</FieldLabel>
          <Input
            id="endpoint-concurrency"
            type="number"
            min={1}
            max={50}
            step={1}
            aria-invalid={invalid('max_concurrency')}
            {...form.register('max_concurrency', { valueAsNumber: true })}
          />
          <FieldDescription>Deliveries in flight at once, from 1 to 50.</FieldDescription>
          <FieldError errors={[errors.max_concurrency]} />
        </Field>
        <Field data-invalid={invalid('retry_on_4xx')}>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              className="size-4 accent-primary"
              {...form.register('retry_on_4xx')}
            />
            Retry on 4xx
          </label>
          <FieldError errors={[errors.retry_on_4xx]} />
        </Field>
        <Button type="submit" disabled={mutation.isPending} className="w-fit">
          Create endpoint
        </Button>
      </FieldGroup>
    </form>
  )
}
