import { useState } from 'react'
import type { MenuItem } from '../types'
import type { Size, Milk, ItemOptions } from '../types'

interface MenuItemCardProps {
  item: MenuItem
  onAdd: (item: MenuItem, options: ItemOptions) => void
}

const SIZE_OPTIONS: { value: Size; label: string; modifier: string }[] = [
  { value: 'small', label: 'Small', modifier: '+$0.00' },
  { value: 'medium', label: 'Medium', modifier: '+$0.50' },
  { value: 'large', label: 'Large', modifier: '+$1.00' },
]

const MILK_OPTIONS: { value: Milk; label: string }[] = [
  { value: 'whole', label: 'Whole' },
  { value: 'oat', label: 'Oat' },
  { value: 'none', label: 'None' },
]

function formatBasePrice(cents: number): string {
  const dollars = Math.floor(cents / 100)
  const remainder = cents % 100
  return `$${dollars}.${String(remainder).padStart(2, '0')}`
}

export function MenuItemCard({ item, onAdd }: MenuItemCardProps) {
  const [size, setSize] = useState<Size>('small')
  const [milk, setMilk] = useState<Milk>('whole')

  function handleAdd() {
    onAdd(item, { size, milk })
  }

  return (
    <div className="menu-item-card" data-testid={`menu-item-${item.id}`}>
      <div className="menu-item-header">
        <span className="menu-item-name" data-testid={`item-name-${item.id}`}>
          {item.name}
        </span>
        <span className="menu-item-price" data-testid={`item-price-${item.id}`}>
          {formatBasePrice(item.basePriceCents)}
        </span>
      </div>

      {item.allowsSize && (
        <div className="option-group" data-testid={`size-group-${item.id}`}>
          <label className="option-label">Size</label>
          <div className="option-pills">
            {SIZE_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                type="button"
                className={`option-pill ${size === opt.value ? 'active' : ''}`}
                onClick={() => setSize(opt.value)}
                data-testid={`size-${opt.value}-${item.id}`}
                aria-pressed={size === opt.value}
              >
                {opt.label}
                <span className="option-modifier">{opt.modifier}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {item.allowsMilk && (
        <div className="option-group" data-testid={`milk-group-${item.id}`}>
          <label className="option-label">Milk</label>
          <div className="option-pills">
            {MILK_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                type="button"
                className={`option-pill ${milk === opt.value ? 'active' : ''}`}
                onClick={() => setMilk(opt.value)}
                data-testid={`milk-${opt.value}-${item.id}`}
                aria-pressed={milk === opt.value}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>
      )}

      <button
        type="button"
        className="add-to-cart-btn"
        onClick={handleAdd}
        data-testid={`add-to-cart-${item.id}`}
      >
        Add to Cart
      </button>
    </div>
  )
}
