import type { MenuItem } from '../types'

/**
 * Full menu from Appendix A.
 * All prices are in integer cents.
 */
export const MENU_ITEMS: MenuItem[] = [
  {
    id: 'espresso',
    category: 'espresso',
    name: 'Espresso',
    basePriceCents: 250,
    allowsSize: true,
    allowsMilk: true,
  },
  {
    id: 'cappuccino',
    category: 'espresso',
    name: 'Cappuccino',
    basePriceCents: 400,
    allowsSize: true,
    allowsMilk: true,
  },
  {
    id: 'latte',
    category: 'espresso',
    name: 'Latte',
    basePriceCents: 450,
    allowsSize: true,
    allowsMilk: true,
  },
  {
    id: 'filter-coffee',
    category: 'brewed',
    name: 'Filter Coffee',
    basePriceCents: 300,
    allowsSize: true,
    allowsMilk: true,
  },
  {
    id: 'cold-brew',
    category: 'brewed',
    name: 'Cold Brew',
    basePriceCents: 425,
    allowsSize: true,
    allowsMilk: true,
  },
  {
    id: 'butter-croissant',
    category: 'pastries',
    name: 'Butter Croissant',
    basePriceCents: 350,
    allowsSize: false,
    allowsMilk: false,
  },
]

/** Size price modifiers in cents */
export const SIZE_MODIFIERS: Record<string, number> = {
  small: 0,
  medium: 50,
  large: 100,
}

export const CATEGORY_LABELS: Record<string, string> = {
  espresso: 'Espresso',
  brewed: 'Brewed',
  pastries: 'Pastries',
}
