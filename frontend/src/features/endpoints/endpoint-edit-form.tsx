import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { toast } from 'sonner'
import { z } from 'zod'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import type { EndpointDetail } from '@/lib/api/types'
import { applyApiErrors } from '@/lib/forms'
import {
  type EndpointChanges,
  splitEventTypes,
  toEndpointFormError,
  updateEndpoint,
  useEndpointSaved,
} from './queries'

// Only required fields and number types are checked here: the API's
// messages (unsafe URL, retry window range, ...) are shown on their fields.
const schema = z.object({
  url: z.string().trim().min(1, 'Enter a URL.'),
  description: z.string(),
  event_types: z.string(),
  retry_window_hours: z.number('Enter a number of hours.'),
  retry_on_4xx: z.boolean(),
  max_concurrency: z.number('Enter a number.').int('Enter a whole number.').min(1).max(50),
})

type Values = z.infer<typeof schema>

const toValues = (endpoint: EndpointDetail): Values => ({
  url: endpoint.url,
  description: endpoint.description ?? '',
  event_types: endpoint.event_types.join(', '),
  retry_window_hours: Math.round((endpoint.retry_window_seconds / 3600) * 100) / 100,
  retry_on_4xx: endpoint.retry_on_4xx,
  max_concurrency: endpoint.max_concurrency,
})

// Only the fields that differ from the saved endpoint, in the API's names and units.
function toChanges(values: Values, endpoint: EndpointDetail) {
  const all: Required<Omit<EndpointChanges, 'enabled'>> = {
    url: values.url.trim(),
    description: values.description.trim(),
    event_types: splitEventTypes(values.event_types),
    retry_window_seconds: Math.round(values.retry_window_hours * 3600),
    retry_on_4xx: values.retry_on_4xx,
    max_concurrency: values.max_concurrency,
  }
  const saved = { ...endpoint, description: endpoint.description ?? '' }
  return Object.fromEntries(
    Object.entries(all).filter(
      ([key, value]) => JSON.stringify(value) !== JSON.stringify(saved[key as keyof typeof all]),
    ),
  ) as EndpointChanges
}

// Edits an endpoint's settings; the parent remounts it (by key) after a save
// so it starts again from the saved values.
export function EndpointEditForm({ endpoint }: { endpoint: EndpointDetail }) {
  const [failure, setFailure] = useState<string | null>(null)
  const saved = useEndpointSaved()
  const form = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: toValues(endpoint),
  })

  const mutation = useMutation({
    mutationFn: (changes: EndpointChanges) => updateEndpoint(endpoint.id, changes),
    onSuccess: async ({ data }) => {
      await saved(data)
      toast.success('Endpoint saved')
    },
    onError: (error) => setFailure(applyApiErrors(form, toEndpointFormError(error))),
  })

  const onSubmit = (values: Values) => {
    setFailure(null)
    const changes = toChanges(values, endpoint)
    if (Object.keys(changes).length === 0) {
      toast('Nothing to save.')
      return
    }
    return mutation.mutateAsync(changes).catch(() => {})
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
        <Field data-invalid={invalid('url')}>
          <FieldLabel htmlFor="edit-endpoint-url">URL</FieldLabel>
          <Input
            id="edit-endpoint-url"
            type="url"
            autoComplete="off"
            aria-invalid={invalid('url')}
            {...form.register('url')}
          />
          <FieldError errors={[errors.url]} />
        </Field>
        <Field data-invalid={invalid('description')}>
          <FieldLabel htmlFor="edit-endpoint-description">Description</FieldLabel>
          <Input
            id="edit-endpoint-description"
            autoComplete="off"
            aria-invalid={invalid('description')}
            {...form.register('description')}
          />
          <FieldError errors={[errors.description]} />
        </Field>
        <Field data-invalid={invalid('event_types')}>
          <FieldLabel htmlFor="edit-endpoint-event-types">Event types</FieldLabel>
          <Input
            id="edit-endpoint-event-types"
            autoComplete="off"
            placeholder="payment.*, refund.created"
            aria-invalid={invalid('event_types')}
            {...form.register('event_types')}
          />
          <FieldDescription>Comma-separated. Leave empty for all event types.</FieldDescription>
          <FieldError errors={[errors.event_types]} />
        </Field>
        <Field data-invalid={invalid('retry_window_hours')}>
          <FieldLabel htmlFor="edit-endpoint-retry-window">Retry window (hours)</FieldLabel>
          <Input
            id="edit-endpoint-retry-window"
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
          <FieldLabel htmlFor="edit-endpoint-concurrency">Concurrency</FieldLabel>
          <Input
            id="edit-endpoint-concurrency"
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
          Save changes
        </Button>
      </FieldGroup>
    </form>
  )
}
