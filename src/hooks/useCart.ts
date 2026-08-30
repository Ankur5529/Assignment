import { useState, useEffect, useCallback } from 'react'
import type { CartLine, MenuItem, ItemOptions } from '../types'

const STORAGE_KEY = 'coffee-cart-v1'

function loadCart(): CartLine[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed as CartLine[]
  } catch {
    return []
  }
}

function saveCart(lines: CartLine[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(lines))
}

/** Stable line key: item id + size + milk */
function lineKey(item: MenuItem, options: ItemOptions): string {
  return `${item.id}:${options.size}:${options.milk}`
}

export interface UseCartReturn {
  lines: CartLine[]
  addItem: (item: MenuItem, options: ItemOptions) => void
  incrementLine: (key: string) => void
  decrementLine: (key: string) => void
  removeLine: (key: string) => void
  clearCart: () => void
}

export function useCart(): UseCartReturn {
  const [lines, setLines] = useState<CartLine[]>(loadCart)

  // Persist on every change
  useEffect(() => {
    saveCart(lines)
  }, [lines])

  const addItem = useCallback((item: MenuItem, options: ItemOptions) => {
    const key = lineKey(item, options)
    setLines((prev) => {
      const existing = prev.find((l) => l.key === key)
      if (existing) {
        // R2 — same item + identical options → increment quantity
        return prev.map((l) =>
          l.key === key ? { ...l, quantity: l.quantity + 1 } : l
        )
      }
      // R3 — different options → new line
      return [...prev, { key, item, options, quantity: 1 }]
    })
  }, [])

  const incrementLine = useCallback((key: string) => {
    setLines((prev) =>
      prev.map((l) => (l.key === key ? { ...l, quantity: l.quantity + 1 } : l))
    )
  }, [])

  const decrementLine = useCallback((key: string) => {
    setLines((prev) => {
      const line = prev.find((l) => l.key === key)
      if (!line) return prev
      // R4 — quantity at 1 → remove line entirely
      if (line.quantity <= 1) {
        return prev.filter((l) => l.key !== key)
      }
      return prev.map((l) =>
        l.key === key ? { ...l, quantity: l.quantity - 1 } : l
      )
    })
  }, [])

  const removeLine = useCallback((key: string) => {
    setLines((prev) => prev.filter((l) => l.key !== key))
  }, [])

  const clearCart = useCallback(() => {
    setLines([])
  }, [])

  return { lines, addItem, incrementLine, decrementLine, removeLine, clearCart }
}
