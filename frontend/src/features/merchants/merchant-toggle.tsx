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
import type { MerchantDetail } from '@/lib/api/types'
import { updateMerchant, useMerchantSaved } from './queries'

// Disabling asks for a confirmation (it stops new deliveries); enabling does not.
export function MerchantToggle({ merchant }: { merchant: MerchantDetail }) {
  const [open, setOpen] = useState(false)
  const saved = useMerchantSaved()

  const mutation = useMutation({
    mutationFn: (enabled: boolean) => updateMerchant(merchant.id, { enabled }),
    onSuccess: async ({ data }) => {
      setOpen(false)
      await saved(data)
      toast.success(data.enabled ? 'Merchant enabled' : 'Merchant disabled')
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

  if (!merchant.enabled) {
    return (
      <div className="flex flex-col items-start gap-2">
        {failure}
        <Button onClick={() => mutation.mutate(true)} disabled={mutation.isPending}>
          Enable merchant
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
          Disable merchant
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Disable {merchant.name}?</DialogTitle>
          <DialogDescription>
            New events for this merchant are rejected until it is enabled again. Its endpoints keep
            their own settings.
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
