import {
  voterSignupSchema,
  politicianContactSchema,
  mediaContactSchema,
  aiLabContactSchema,
  partnershipInquirySchema,
  careersApplicationSchema,
  supportRequestSchema,
} from './schemas'
import { submitForm } from './submit'
import type { Audience } from './endpoints'
import type { ZodSchema } from 'zod'

const schemas: Record<Audience, ZodSchema> = {
  voter: voterSignupSchema,
  politician: politicianContactSchema,
  media: mediaContactSchema,
  aiLab: aiLabContactSchema,
  partnership: partnershipInquirySchema,
  careers: careersApplicationSchema,
  support: supportRequestSchema,
}

const endpoints: Record<Audience, string | undefined> = {
  voter: import.meta.env.PUBLIC_VOTER_FORM_ENDPOINT,
  politician: import.meta.env.PUBLIC_POLITICIAN_FORM_ENDPOINT,
  media: import.meta.env.PUBLIC_MEDIA_FORM_ENDPOINT,
  aiLab: import.meta.env.PUBLIC_AI_LAB_FORM_ENDPOINT,
  partnership: import.meta.env.PUBLIC_PARTNERSHIP_FORM_ENDPOINT,
  careers: import.meta.env.PUBLIC_CAREERS_FORM_ENDPOINT,
  support: import.meta.env.PUBLIC_SUPPORT_FORM_ENDPOINT,
}

// Maps the frontend audience id to the value the contact Lambda expects.
// The voter audience hits /subscribe, which doesn't read form_type.
const formTypeForAudience: Record<Audience, string | undefined> = {
  voter: undefined,
  politician: 'politician',
  media: 'media',
  aiLab: 'ai',
  partnership: 'partnership',
  careers: 'careers',
  support: 'support',
}

const VALID_AUDIENCES: readonly Audience[] = [
  'voter',
  'politician',
  'media',
  'aiLab',
  'partnership',
  'careers',
  'support',
]

function isAudience(s: string | undefined): s is Audience {
  return s !== undefined && (VALID_AUDIENCES as readonly string[]).includes(s)
}

type StatusKind = 'idle' | 'submitting' | 'success' | 'error' | 'pending'

type TurnstileGlobal = {
  reset: (target?: string | HTMLElement) => void
}

declare global {
  interface Window {
    turnstile?: TurnstileGlobal
  }
}

// Signup forms say "you're on the list"; a support request needs to say the
// ticket was received. A form opts out of the default via data-success-message.
function successMessage(form: HTMLFormElement): string {
  return form.dataset.successMessage || "Thanks — you're on the list. We'll be in touch."
}

function setStatus(form: HTMLFormElement, kind: StatusKind, message: string) {
  const status = form.querySelector<HTMLElement>('[data-form-status]')
  if (!status) return
  status.dataset.kind = kind
  status.textContent = message
  status.hidden = !message
}

function showFieldError(form: HTMLFormElement, fieldName: string, message: string) {
  const errorEl = form.querySelector<HTMLElement>(`[data-error-for="${fieldName}"]`)
  const inputEl = form.querySelector<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>(
    `[name="${fieldName}"]`,
  )
  if (errorEl) {
    errorEl.textContent = message
    errorEl.hidden = false
  }
  if (inputEl) {
    inputEl.setAttribute('aria-invalid', 'true')
  }
}

function clearFieldErrors(form: HTMLFormElement) {
  form.querySelectorAll<HTMLElement>('[data-error-for]').forEach((el) => {
    el.textContent = ''
    el.hidden = true
  })
  form.querySelectorAll<HTMLElement>('[aria-invalid="true"]').forEach((el) => {
    el.removeAttribute('aria-invalid')
  })
}

function readForm(form: HTMLFormElement): Record<string, string | File> {
  const data: Record<string, string | File> = {}
  const fd = new FormData(form)
  for (const [key, value] of fd.entries()) {
    if (value instanceof File) {
      // Browsers include an empty File when the user hasn't selected one.
      // Skip it so the zod schema's "required" rule fires cleanly.
      if (value.size === 0 && value.name === '') continue
      data[key] = value
    } else {
      data[key] = value
    }
  }
  return data
}

const camelToSnake = (key: string) => key.replace(/[A-Z]/g, (m) => '_' + m.toLowerCase())

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result
      if (typeof result !== 'string') {
        reject(new Error('Unexpected file reader result.'))
        return
      }
      const comma = result.indexOf(',')
      resolve(comma >= 0 ? result.slice(comma + 1) : result)
    }
    reader.onerror = () => reject(reader.error ?? new Error('File read failed.'))
    reader.readAsDataURL(file)
  })
}

async function toWirePayload(
  audience: Audience,
  parsed: Record<string, unknown>,
  token: string,
): Promise<Record<string, unknown>> {
  const wire: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(parsed)) {
    if (v === undefined || v === null || v === '') continue
    if (v instanceof File) {
      const key = camelToSnake(k)
      wire[`${key}_base64`] = await fileToBase64(v)
      wire[`${key}_filename`] = v.name
      continue
    }
    wire[camelToSnake(k)] = v
  }
  const formType = formTypeForAudience[audience]
  if (formType) wire.form_type = formType
  wire.turnstile_token = token
  return wire
}

function getTurnstileToken(form: HTMLFormElement): string {
  const input = form.querySelector<HTMLInputElement>('[name="cf-turnstile-response"]')
  return input?.value?.trim() ?? ''
}

function resetTurnstile(form: HTMLFormElement) {
  const widget = form.querySelector<HTMLElement>('.cf-turnstile')
  if (widget && window.turnstile) {
    try {
      window.turnstile.reset(widget)
    } catch {
      /* widget may not be rendered yet — safe to ignore */
    }
  }
}

function attachForm(form: HTMLFormElement) {
  const audience = form.dataset.voxiviumForm
  if (!isAudience(audience)) {
    return
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault()
    clearFieldErrors(form)

    const honeypot = form.querySelector<HTMLInputElement>('[name="hp"]')
    if (honeypot && honeypot.value.trim() !== '') {
      // Silently "succeed" — bots see what they expect, real users never fill this.
      setStatus(form, 'success', successMessage(form))
      form.reset()
      return
    }

    const raw = readForm(form)
    delete raw.hp
    delete raw['cf-turnstile-response']

    const parsed = schemas[audience].safeParse(raw)
    if (!parsed.success) {
      const seen = new Set<string>()
      for (const issue of parsed.error.issues) {
        const field = String(issue.path[0])
        if (seen.has(field)) continue
        seen.add(field)
        showFieldError(form, field, issue.message)
      }
      setStatus(form, 'error', 'Please fix the highlighted fields and try again.')
      const firstInvalid = form.querySelector<HTMLElement>('[aria-invalid="true"]')
      firstInvalid?.focus()
      return
    }

    const turnstileToken = getTurnstileToken(form)
    if (!turnstileToken) {
      showFieldError(form, 'turnstile', 'Please complete the verification challenge.')
      setStatus(form, 'error', 'Please complete the verification challenge and try again.')
      return
    }

    const endpoint = endpoints[audience]
    if (!endpoint) {
      setStatus(
        form,
        'pending',
        "We're not yet accepting submissions for this audience. Sign up for voter updates to be first in line.",
      )
      return
    }

    const submitButton = form.querySelector<HTMLButtonElement>('button[type="submit"]')
    setStatus(form, 'submitting', 'Submitting…')
    if (submitButton) submitButton.disabled = true

    let payload: Record<string, unknown>
    try {
      payload = await toWirePayload(
        audience,
        parsed.data as Record<string, unknown>,
        turnstileToken,
      )
    } catch (err) {
      if (submitButton) submitButton.disabled = false
      console.error('Failed to build wire payload', err)
      setStatus(form, 'error', 'We couldn’t read your file. Please try again.')
      resetTurnstile(form)
      return
    }

    const result = await submitForm(endpoint, payload)
    if (submitButton) submitButton.disabled = false

    if (result.ok) {
      setStatus(form, 'success', successMessage(form))
      form.reset()
      resetTurnstile(form)
    } else {
      setStatus(form, 'error', result.error)
      // Tokens are single-use — give the user a fresh challenge for the retry.
      resetTurnstile(form)
    }
  })
}

function init() {
  document.querySelectorAll<HTMLFormElement>('form[data-voxivium-form]').forEach(attachForm)
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init)
} else {
  init()
}
