import type { MenuItem } from '../types'
import type { ItemOptions } from '../types'
import { MenuItemCard } from './MenuItem'

interface MenuSectionProps {
  category: string
  label: string
  items: MenuItem[]
  onAdd: (item: MenuItem, options: ItemOptions) => void
}

export function MenuSection({ category, label, items, onAdd }: MenuSectionProps) {
  const categoryItems = items.filter((i) => i.category === category)
  if (categoryItems.length === 0) return null

  return (
    <section
      className="menu-section"
      data-testid={`menu-section-${category}`}
      aria-labelledby={`section-heading-${category}`}
    >
      <h2
        className="menu-section-heading"
        id={`section-heading-${category}`}
        data-testid={`section-heading-${category}`}
      >
        {label}
      </h2>
      <div className="menu-section-grid">
        {categoryItems.map((item) => (
          <MenuItemCard key={item.id} item={item} onAdd={onAdd} />
        ))}
      </div>
    </section>
  )
}
