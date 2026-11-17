import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import type { MerchantDetail } from '@/lib/api/types'
import { applyApiErrors } from '@/lib/forms'

const schema = z.object({
  name: z.string().trim().min(1, 'Enter a name.'),
})

type Values = z.infer<typeof schema>

type Props = {
  // `id` of the name input, unique on the page.
  id: string
  defaultName?: string
  submitLabel: string
  save: (name: string) => Promise<{ data: MerchantDetail }>
  onSaved: (merchant: MerchantDetail) => Promise<void> | void
}

// The merchant's name, for creating or renaming one; the API's messages for
// `name` are shown next to the field.
export function MerchantNameForm({ id, defaultName = '', submitLabel, save, onSaved }: Props) {
  const [failure, setFailure] = useState<string | null>(null)
  const form = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { name: defaultName },
  })

  const mutation = useMutation({
    mutationFn: ({ name }: Values) => save(name),
    onSuccess: ({ data }) => onSaved(data),
    onError: (error) => setFailure(applyApiErrors(form, error)),
  })

  const onSubmit = (values: Values) => {
    setFailure(null)
    return mutation.mutateAsync(values).catch(() => {})
  }

  const nameError = form.formState.errors.name

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} noValidate className="max-w-md">
      <FieldGroup>
        {failure && (
          <Alert variant="destructive">
            <AlertDescription>{failure}</AlertDescription>
          </Alert>
        )}
        <Field data-invalid={nameError ? true : undefined}>
          <FieldLabel htmlFor={id}>Name</FieldLabel>
          <Input
            id={id}
            autoComplete="off"
            aria-invalid={nameError ? true : undefined}
            {...form.register('name')}
          />
          <FieldError errors={[nameError]} />
        </Field>
        <Button type="submit" disabled={mutation.isPending} className="w-fit">
          {submitLabel}
        </Button>
      </FieldGroup>
    </form>
  )
}
