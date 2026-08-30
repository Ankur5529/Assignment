import { useState } from 'react'
import type { CartLine, CheckoutForm, ConfirmedOrder } from '../types'
import { subtotalCents, taxCents } from '../utils/money'

interface OrderFormProps {
  lines: CartLine[]
  onConfirm: (order: ConfirmedOrder) => void
  onBack: () => void
}

/** Generate a 6-digit order number matching /^ORD-\d{6}$/ */
function generateOrderNumber(): string {
  const digits = String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0')
  return `ORD-${digits}`
}

/** Validate phone: exactly 10 digits (digits only after stripping non-digits) */
function isValidPhone(phone: string): boolean {
  const digitsOnly = phone.replace(/\D/g, '')
  return digitsOnly.length === 10
}

export function OrderForm({ lines, onConfirm, onBack }: OrderFormProps) {
  const [form, setForm] = useState<CheckoutForm>({ name: '', phone: '' })
  const [submitted, setSubmitted] = useState(false)

  const nameValid = form.name.trim().length > 0
  const phoneValid = isValidPhone(form.phone)
  // R6 — submit disabled until name non-empty AND exactly 10 phone digits
  const canSubmit = nameValid && phoneValid

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!canSubmit) return
    setSubmitted(true)

    const sub = subtotalCents(lines)
    const tax = taxCents(sub)

    const order: ConfirmedOrder = {
      orderNumber: generateOrderNumber(),
      lines: [...lines],
      subtotalCents: sub,
      taxCents: tax,
      totalCents: sub + tax,
    }
    onConfirm(order)
  }

  return (
    <div className="order-form-wrapper" data-testid="order-form">
      <button
        type="button"
        className="back-btn"
        onClick={onBack}
        data-testid="back-to-cart-btn"
      >
        ← Back to cart
      </button>

      <h2 className="form-heading">Complete your order</h2>

      <form onSubmit={handleSubmit} noValidate data-testid="checkout-form">
        <div className="form-field">
          <label htmlFor="customer-name" className="form-label">
            Name
          </label>
          <input
            id="customer-name"
            type="text"
            className="form-input"
            placeholder="Your name"
            value={form.name}
            onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
            data-testid="input-name"
            autoComplete="name"
          />
          {submitted && !nameValid && (
            <span className="form-error" data-testid="error-name">
              Name is required
            </span>
          )}
        </div>

        <div className="form-field">
          <label htmlFor="customer-phone" className="form-label">
            Phone (10 digits)
          </label>
          <input
            id="customer-phone"
            type="tel"
            className="form-input"
            placeholder="5551234567"
            value={form.phone}
            onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
            data-testid="input-phone"
            autoComplete="tel"
            maxLength={15}
          />
          {submitted && !phoneValid && (
            <span className="form-error" data-testid="error-phone">
              Enter exactly 10 digits
            </span>
          )}
        </div>

        <button
          type="submit"
          className="submit-btn"
          disabled={!canSubmit}
          data-testid="submit-order-btn"
        >
          Place Order
        </button>
      </form>
    </div>
  )
}
