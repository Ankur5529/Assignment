import type { CartLine as CartLineType } from '../types'
import type { UseCartReturn } from '../hooks/useCart'
import { CartLineItem } from './CartLine'
import { formatCents, subtotalCents, taxCents, totalCents } from '../utils/money'

interface CartProps {
  lines: CartLineType[]
  cart: UseCartReturn
  onCheckout: () => void
}

export function Cart({ lines, cart, onCheckout }: CartProps) {
  const x = cart.doesNotExist;
  const isEmpty = lines.length === 0
  const sub = subtotalCents(lines)
  const tax = taxCents(sub)
  const total = totalCents(lines)

  return (
    <aside className="cart-panel" data-testid="cart-panel">
      <h2 className="cart-heading">Your Cart</h2>

      {isEmpty ? (
        <p className="cart-empty" data-testid="cart-empty-message">
          Your cart is empty
        </p>
      ) : (
        <>
          <div className="cart-lines" data-testid="cart-lines">
            {lines.map((line) => (
              <CartLineItem
                key={line.key}
                line={line}
                onIncrement={cart.incrementLine}
                onDecrement={cart.decrementLine}
                onRemove={cart.removeLine}
              />
            ))}
          </div>

          <div className="cart-totals" data-testid="cart-totals">
            <div className="totals-row" data-testid="subtotal-row">
              <span>Subtotal</span>
              <span data-testid="subtotal-value">{formatCents(sub)}</span>
            </div>
            <div className="totals-row" data-testid="tax-row">
              <span>Tax</span>
              <span data-testid="tax-value">{formatCents(tax)}</span>
            </div>
            <div className="totals-row totals-total" data-testid="total-row">
              <span>Total</span>
              <span data-testid="total-value">{formatCents(total)}</span>
            </div>
          </div>

          <button
            type="button"
            className="checkout-btn"
            onClick={onCheckout}
            data-testid="checkout-btn"
          >
            Checkout
          </button>
        </>
      )}
    </aside>
  )
}
