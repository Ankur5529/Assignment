import type { ConfirmedOrder } from '../types'
import { formatCents, lineTotalCents } from '../utils/money'

interface ConfirmationProps {
  order: ConfirmedOrder
  onNewOrder: () => void
}

export function Confirmation({ order, onNewOrder }: ConfirmationProps) {
  return (
    <div className="confirmation-wrapper" data-testid="confirmation-screen">
      <div className="confirmation-card">
        <div className="confirmation-icon" aria-hidden="true">☕</div>
        <h2 className="confirmation-heading" data-testid="confirmation-heading">
          Order confirmed
        </h2>
        <p className="order-number" data-testid="order-number">
          {order.orderNumber}
        </p>

        <div className="confirmation-lines" data-testid="confirmation-lines">
          {order.lines.map((line) => (
            <div
              key={line.key}
              className="confirmation-line"
              data-testid={`confirmation-line-${line.key}`}
            >
              <span className="conf-line-name">
                {line.item.name}
                {line.item.allowsSize && (
                  <span className="conf-line-opts">
                    {' '}
                    ({line.options.size}
                    {line.options.milk !== 'none' ? `, ${line.options.milk} milk` : ''})
                  </span>
                )}
                {' '}×{line.quantity}
              </span>
              <span
                className="conf-line-total"
                data-testid={`confirmation-line-total-${line.key}`}
              >
                {formatCents(lineTotalCents(line))}
              </span>
            </div>
          ))}
        </div>

        <div className="confirmation-totals" data-testid="confirmation-totals">
          <div className="totals-row" data-testid="conf-subtotal-row">
            <span>Subtotal</span>
            <span data-testid="conf-subtotal-value">
              {formatCents(order.subtotalCents)}
            </span>
          </div>
          <div className="totals-row" data-testid="conf-tax-row">
            <span>Tax</span>
            <span data-testid="conf-tax-value">{formatCents(order.taxCents)}</span>
          </div>
          <div className="totals-row totals-total" data-testid="conf-total-row">
            <span>Total</span>
            <span data-testid="conf-total-value">
              {formatCents(order.totalCents)}
            </span>
          </div>
        </div>

        <button
          type="button"
          className="new-order-btn"
          onClick={onNewOrder}
          data-testid="new-order-btn"
        >
          Place another order
        </button>
      </div>
    </div>
  )
}
