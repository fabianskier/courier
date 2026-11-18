import { Socket } from 'phoenix'

// The dashboard socket as the rest of the SPA sees it: tests swap in a fake
// through `setTransportFactory`, so only this file knows about `phoenix`.

// `connecting` until the first open; `reconnecting` whenever it drops.
export type LiveStatus = 'connecting' | 'live' | 'reconnecting'

export type NoticeName =
  | 'event_ingested'
  | 'delivery_changed'
  | 'endpoint_changed'
  | 'merchant_changed'
export type NoticePayload = Record<string, unknown>
export type NoticeHandler = (name: NoticeName, payload: NoticePayload) => void

export const noticeNames: readonly NoticeName[] = [
  'event_ingested',
  'delivery_changed',
  'endpoint_changed',
  'merchant_changed',
]

export interface LiveTransport {
  connect(): void
  join(topic: string, onNotice: NoticeHandler): void
  onStatus(handler: (status: Exclude<LiveStatus, 'connecting'>) => void): void
  disconnect(): void
}

export type TransportFactory = (token: string) => LiveTransport

// The key travels as the WebSocket auth token (a `Sec-WebSocket-Protocol`
// header), never in the URL. Phoenix's default backoff reconnects it.
export function phoenixTransport(
  token: string,
  SocketClass: typeof Socket = Socket,
): LiveTransport {
  const socket = new SocketClass('/socket', { authToken: token })
  return {
    connect: () => socket.connect(),
    join(topic, onNotice) {
      const channel = socket.channel(topic)
      for (const name of noticeNames) {
        channel.on(name, (payload: NoticePayload) => onNotice(name, payload))
      }
      channel.join()
    },
    onStatus(handler) {
      socket.onOpen(() => handler('live'))
      socket.onError(() => handler('reconnecting'))
      socket.onClose(() => handler('reconnecting'))
    },
    disconnect: () => socket.disconnect(),
  }
}

let factory: TransportFactory = phoenixTransport

export function setTransportFactory(next: TransportFactory) {
  factory = next
}

export const createTransport = (token: string) => factory(token)
