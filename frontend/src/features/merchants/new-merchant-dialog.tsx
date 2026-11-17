import { useNavigate } from '@tanstack/react-router'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { MerchantNameForm } from './merchant-name-form'
import { createMerchant, useMerchantSaved } from './queries'

// "New merchant": a name, then the new merchant's page.
export function NewMerchantDialog() {
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()
  const saved = useMerchantSaved()

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>New merchant</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New merchant</DialogTitle>
          <DialogDescription>It starts enabled, with no endpoints.</DialogDescription>
        </DialogHeader>
        <MerchantNameForm
          id="new-merchant-name"
          submitLabel="Create merchant"
          save={createMerchant}
          onSaved={async (merchant) => {
            await saved(merchant)
            setOpen(false)
            await navigate({ to: '/merchants/$merchantId', params: { merchantId: merchant.id } })
          }}
        />
      </DialogContent>
    </Dialog>
  )
}
