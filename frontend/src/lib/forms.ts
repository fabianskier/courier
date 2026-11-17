import type { FieldValues, Path, UseFormReturn } from 'react-hook-form'
import { ApiError } from '@/lib/api/client'

// Shows a failed submission: each `422` detail for a field of the form is set
// on that field; anything else (no details, a field the form does not have,
// another error) comes back as a message for an alert, or null when none is left.
export function applyApiErrors<T extends FieldValues>(
  form: UseFormReturn<T>,
  error: unknown,
): string | null {
  if (!(error instanceof ApiError)) return 'The request failed.'
  if (error.status !== 422 || !error.details) return error.message

  const fields = Object.keys(form.getValues())
  let unplaced = false
  for (const [field, messages] of Object.entries(error.details)) {
    if (fields.includes(field)) {
      form.setError(field as Path<T>, { type: 'server', message: messages.join(' ') })
    } else {
      unplaced = true
    }
  }
  return unplaced ? error.message : null
}
