import { setTransportFactory } from '@/lib/live/transport'

// jsdom has no dashboard socket to reach: by default every test gets a
// transport that never connects. `live-updates.test.tsx` installs a fake it drives.
setTransportFactory(() => ({
  connect: () => {},
  join: () => {},
  onStatus: () => {},
  disconnect: () => {},
}))
