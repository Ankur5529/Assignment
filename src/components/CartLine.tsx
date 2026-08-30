import type { CartLine } from '../types'
import { formatCents, lineTotalCents } from '../utils/money'

interface CartLineItemProps {
  line: CartLine
  onIncrement: (key: string) => void
  onDecrement: (key: string) => void
  onRemove: (key: string) => void
}

function optionSummary(line: CartLine): string {
  const parts: string[] = []
  if (line.item.allowsSize) {
    parts.push(line.options.size.charAt(0).toUpperCase() + line.options.size.slice(1))
  }
  if (line.item.allowsMilk && line.options.milk !== 'none') {
    parts.push(`${line.options.milk.charAt(0).toUpperCase() + line.options.milk.slice(1)} milk`)
  }
  return parts.join(', ')
}

export function CartLineItem({ line, onIncrement, onDecrement, onRemove }: CartLineItemProps) {
  const summary = optionSummary(line)

  return (
    <div className="cart-line" data-testid={`cart-line-${line.key}`}>
      <div className="cart-line-info">
        <span className="cart-line-name" data-testid={`cart-line-name-${line.key}`}>
          {line.item.name}
        </span>
        {summary && (
          <span className="cart-line-options" data-testid={`cart-line-options-${line.key}`}>
            {summary}
          </span>
        )}
        <span className="cart-line-total" data-testid={`cart-line-total-${line.key}`}>
          {formatCents(lineTotalCents(line))}
        </span>
      </div>

      <div className="cart-line-controls">
        <button
          type="button"
          className="qty-btn"
          onClick={() => onDecrement(line.key)}
          data-testid={`decrement-${line.key}`}
          aria-label={`Decrease quantity of ${line.item.name}`}
        >
          −
        </button>
        <span className="qty-value" data-testid={`quantity-${line.key}`}>
          {line.quantity}
        </span>
        <button
          type="button"
          className="qty-btn"
          onClick={() => onIncrement(line.key)}
          data-testid={`increment-${line.key}`}
          aria-label={`Increase quantity of ${line.item.name}`}
        >
          +
        </button>
        <button
          type="button"
          className="remove-btn"
          onClick={() => onRemove(line.key)}
          data-testid={`remove-${line.key}`}
          aria-label={`Remove ${line.item.name} from cart`}
        >
          ✕
        </button>
      </div>
    </div>
  )
}
