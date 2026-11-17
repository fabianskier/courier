import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { toast } from 'sonner'
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
import { updateEndpoint, useEndpointSaved } from './queries'

// Disabling asks for a confirmation (it stops new deliveries); enabling does not.
export function EndpointToggle({ endpoint }: { endpoint: EndpointDetail }) {
  const [open, setOpen] = useState(false)
  const saved = useEndpointSaved()

  const mutation = useMutation({
    mutationFn: (enabled: boolean) => updateEndpoint(endpoint.id, { enabled }),
    onSuccess: async ({ data }) => {
      setOpen(false)
      await saved(data)
      toast.success(data.enabled ? 'Endpoint enabled' : 'Endpoint disabled')
    },
  })

  const error = mutation.error
  const message = error instanceof ApiError ? error.message : error && 'The change failed.'
  const failure = message && (
    <Alert variant="destructive">
      <AlertTitle>The change was refused.</AlertTitle>
      <AlertDescription>{message}</AlertDescription>
    </Alert>
  )

  if (!endpoint.enabled) {
    return (
      <div className="flex flex-col items-start gap-2">
        {failure}
        <Button onClick={() => mutation.mutate(true)} disabled={mutation.isPending}>
          Enable endpoint
        </Button>
      </div>
    )
  }

  const onOpenChange = (next: boolean) => {
    if (mutation.isPending) return
    if (!next) mutation.reset()
    setOpen(next)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        <Button variant="destructive" className="self-start">
          Disable endpoint
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Disable this endpoint?</DialogTitle>
          <DialogDescription>
            No new deliveries are made to {endpoint.url} until it is enabled again.
          </DialogDescription>
        </DialogHeader>
        {failure}
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline" disabled={mutation.isPending}>
              Cancel
            </Button>
          </DialogClose>
          <Button
            variant="destructive"
            onClick={() => mutation.mutate(false)}
            disabled={mutation.isPending}
          >
            Disable
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
