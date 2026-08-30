// ─── Domain types ──────────────────────────────────────────────────────────────

/** Size modifier for espresso + brewed drinks */
export type Size = 'small' | 'medium' | 'large'

/** Milk option */
export type Milk = 'whole' | 'oat' | 'none'

/** A single item on the menu */
export interface MenuItem {
  id: string
  category: 'espresso' | 'brewed' | 'pastries'
  name: string
  /** Base price in integer cents */
  basePriceCents: number
  allowsSize: boolean
  allowsMilk: boolean
}

/** The user's chosen options for an ordered item */
export interface ItemOptions {
  size: Size
  milk: Milk
}

/**
 * A line in the shopping cart — one unique (item + options) combination.
 * Quantity is always ≥ 1.
 */
export interface CartLine {
  /** Stable key = `${menuItem.id}:${size}:${milk}` */
  key: string
  item: MenuItem
  options: ItemOptions
  quantity: number
}

/** Checkout form state */
export interface CheckoutForm {
  name: string
  phone: string
}

/** Confirmed order shown on the confirmation screen */
export interface ConfirmedOrder {
  orderNumber: string
  lines: CartLine[]
  subtotalCents: number
  taxCents: number
  totalCents: number
}
