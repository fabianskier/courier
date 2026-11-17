import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { ApiError } from '@/lib/api/client'
import type { EndpointDetail } from '@/lib/api/types'
import { formatDateTime } from '@/lib/format'
import { rotateEndpointSecret, useEndpointSaved } from './queries'
import { SecretReveal } from './secret-reveal'

// Rotates the signing secret after a confirmation, then shows the new secret
// once in the dialog. The secret lives only in this component's state and is
// dropped when the dialog closes.
export function RotateSecretDialog({ endpoint }: { endpoint: EndpointDetail }) {
  const [open, setOpen] = useState(false)
  const [rotated, setRotated] = useState<{ secret: string; expiresAt: string | null } | null>(null)
  const saved = useEndpointSaved()

  const mutation = useMutation({
    // Returns the endpoint without its secret, so the mutation cache never holds it.
    mutationFn: async () => {
      const { endpoint: updated, secret } = await rotateEndpointSecret(endpoint.id)
      setRotated({ secret, expiresAt: updated.previous_secret_expires_at })
      return updated
    },
    onSuccess: (updated) => saved(updated),
  })

  const onOpenChange = (next: boolean) => {
    if (mutation.isPending) return
    if (!next) {
      setRotated(null)
      mutation.reset()
    }
    setOpen(next)
  }

  const error = mutation.error
  const message = error instanceof ApiError ? error.message : error && 'The rotation failed.'

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        <Button variant="outline" className="self-start">
          Rotate secret
        </Button>
      </DialogTrigger>
      <DialogContent>
        {rotated ? (
          <>
            <DialogHeader>
              <DialogTitle>New signing secret</DialogTitle>
              <DialogDescription>
                {rotated.expiresAt
                  ? `The previous secret signs until ${formatDateTime(rotated.expiresAt)}.`
                  : 'The previous secret no longer signs.'}
              </DialogDescription>
            </DialogHeader>
            <SecretReveal secret={rotated.secret} id="rotated-secret" />
            <DialogFooter>
              <DialogClose asChild>
                <Button>Done</Button>
              </DialogClose>
            </DialogFooter>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>Rotate the signing secret?</DialogTitle>
              <DialogDescription>
                A new secret signs deliveries from now on. The previous secret keeps signing for 24
                hours, so the receiver can switch over.
              </DialogDescription>
            </DialogHeader>
            {message && (
              <Alert variant="destructive">
                <AlertTitle>The rotation was refused.</AlertTitle>
                <AlertDescription>{message}</AlertDescription>
              </Alert>
            )}
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="outline" disabled={mutation.isPending}>
                  Cancel
                </Button>
              </DialogClose>
              <Button onClick={() => mutation.mutate()} disabled={mutation.isPending}>
                Rotate
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
