export type SubmitResult<T> = { ok: true; data: T } | { ok: false; error: string; status?: number }

export async function submitForm<TIn, TOut = unknown>(
  endpoint: string,
  payload: TIn,
  init?: { signal?: AbortSignal; timeoutMs?: number },
): Promise<SubmitResult<TOut>> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), init?.timeoutMs ?? 10_000)
  const signal = init?.signal ? composeSignals(controller.signal, init.signal) : controller.signal

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal,
    })
    if (!response.ok) {
      return { ok: false, error: `Request failed (${response.status}).`, status: response.status }
    }
    const data = (await response.json().catch(() => ({}))) as TOut
    return { ok: true, data }
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      return { ok: false, error: 'Request timed out. Please try again.' }
    }
    return { ok: false, error: 'Network error. Please try again.' }
  } finally {
    clearTimeout(timeout)
  }
}

function composeSignals(...signals: AbortSignal[]): AbortSignal {
  if (signals.length === 1) return signals[0]
  const controller = new AbortController()
  const onAbort = (signal: AbortSignal) => {
    controller.abort(signal.reason)
  }
  for (const s of signals) {
    if (s.aborted) {
      onAbort(s)
      break
    }
    s.addEventListener('abort', () => onAbort(s), { once: true })
  }
  return controller.signal
}
