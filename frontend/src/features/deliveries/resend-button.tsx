import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
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
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { useMe } from '@/features/auth/session'
import { apiFetch, ApiError } from '@/lib/api/client'
import type { DeliveryDetail, DeliveryStatus } from '@/lib/api/types'

const terminal: DeliveryStatus[] = ['succeeded', 'failed']
const needsWrite = 'Resending needs the write scope.'

// Resends a terminal delivery after a confirmation naming the endpoint URL;
// hidden while pending or skipped, disabled for keys without `write`.
export function ResendButton({
  delivery,
  endpointUrl,
}: {
  delivery: Pick<DeliveryDetail, 'id' | 'status'>
  endpointUrl: string
}) {
  const { scopes } = useMe()

  if (!terminal.includes(delivery.status)) return null
  if (!scopes.includes('write')) return <ReadOnlyResend />
  return <ResendDialog deliveryId={delivery.id} endpointUrl={endpointUrl} />
}

function ReadOnlyResend() {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <Tooltip>
        <TooltipTrigger asChild>
          {/* A disabled button gets no pointer events: the wrapper shows the tooltip. */}
          <span tabIndex={0} className="inline-flex">
            <Button disabled aria-describedby="resend-needs-write">
              Resend
            </Button>
          </span>
        </TooltipTrigger>
        <TooltipContent>{needsWrite}</TooltipContent>
      </Tooltip>
      <p id="resend-needs-write" className="text-sm text-muted-foreground">
        {needsWrite}
      </p>
    </div>
  )
}

function ResendDialog({ deliveryId, endpointUrl }: { deliveryId: string; endpointUrl: string }) {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const mutation = useMutation({
    mutationFn: () =>
      apiFetch<{ data: DeliveryDetail }>(`/deliveries/${encodeURIComponent(deliveryId)}/resend`, {
        method: 'POST',
      }),
    onSuccess: async ({ data }) => {
      setOpen(false)
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['deliveries'] }),
        queryClient.invalidateQueries({ queryKey: ['events'] }),
      ])
      toast.success('Resend created')
      await navigate({ to: '/deliveries/$deliveryId', params: { deliveryId: data.id } })
    },
  })

  const onOpenChange = (next: boolean) => {
    if (mutation.isPending) return
    if (!next) mutation.reset()
    setOpen(next)
  }

  const error = mutation.error
  const message = error instanceof ApiError ? error.message : error && 'The resend failed.'

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        <Button className="self-start">Resend</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Resend this delivery?</DialogTitle>
          <DialogDescription>
            A new delivery of the same event will be sent to{' '}
            <span className="font-mono break-all">{endpointUrl}</span>.
          </DialogDescription>
        </DialogHeader>
        {message && (
          <Alert variant="destructive">
            <AlertTitle>The resend was refused.</AlertTitle>
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
            {mutation.isPending ? 'Resending…' : 'Resend'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
