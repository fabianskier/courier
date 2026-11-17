import { CopyIcon, TriangleAlertIcon } from 'lucide-react'
import { toast } from 'sonner'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'

type Props = { secret: string; id?: string }

// A signing secret the API returned once (after creating an endpoint or
// rotating its secret). It lives only in the caller's state while shown.
export function SecretReveal({ secret, id = 'signing-secret' }: Props) {
  const copy = () =>
    navigator.clipboard.writeText(secret).then(
      () => toast.success('Secret copied'),
      () => toast.error('The secret could not be copied.'),
    )

  return (
    <div className="flex flex-col gap-4">
      <Alert>
        <TriangleAlertIcon aria-hidden="true" />
        <AlertDescription>This secret will not be shown again. Store it now.</AlertDescription>
      </Alert>
      <Field>
        <FieldLabel htmlFor={id}>Signing secret</FieldLabel>
        <div className="flex gap-2">
          <Input
            id={id}
            readOnly
            value={secret}
            autoComplete="off"
            spellCheck={false}
            className="font-mono"
            onFocus={(e) => e.currentTarget.select()}
          />
          <Button type="button" variant="outline" onClick={() => void copy()}>
            <CopyIcon aria-hidden="true" />
            Copy
          </Button>
        </div>
      </Field>
    </div>
  )
}
