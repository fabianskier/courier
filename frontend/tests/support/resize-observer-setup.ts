// jsdom has no ResizeObserver; Radix poppers (sidebar tooltips, the merchant
// switcher menu) measure their anchor with it when they open.
class ResizeObserverStub implements ResizeObserver {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}

globalThis.ResizeObserver ??= ResizeObserverStub
