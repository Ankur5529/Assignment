import type { CartLine } from '../types'
import { SIZE_MODIFIERS } from '../data/menu'

// ─── Formatting ────────────────────────────────────────────────────────────────

/**
 * Format an integer number of cents to a display string.
 * Always shows exactly two decimal places.
 * e.g. 450 → "$4.50", 1000 → "$10.00"
 */
export function formatCents(cents: number): string {
  const dollars = Math.floor(cents / 100)
  const remainder = Math.abs(cents % 100)
  return `$${dollars}.${String(remainder).padStart(2, '0')}`
}

// ─── Line totals ───────────────────────────────────────────────────────────────

/**
 * Compute the unit price (in cents) for a single item+options combination.
 * For items without size options the size modifier is 0.
 */
export function unitPriceCents(line: CartLine): number {
  const sizeModifier = line.item.allowsSize
    ? (SIZE_MODIFIERS[line.options.size] ?? 0)
    : 0
  return line.item.basePriceCents + sizeModifier
}

/**
 * Line total = unit price × quantity.
 */
export function lineTotalCents(line: CartLine): number {
  return unitPriceCents(line) * line.quantity
}

// ─── Order totals ──────────────────────────────────────────────────────────────

/** Sum of all line totals */
export function subtotalCents(lines: CartLine[]): number {
  return lines.reduce((sum, line) => sum + lineTotalCents(line), 0)
}

/** 8 % tax, rounded to nearest cent */
export function taxCents(subtotal: number): number {
  return Math.round(subtotal * 0.08)
}

/** Order total = subtotal + tax */
export function totalCents(lines: CartLine[]): number {
  const sub = subtotalCents(lines)
  return sub + taxCents(sub)
}
