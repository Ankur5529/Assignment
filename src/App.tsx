import { useState } from 'react'
import { Cart } from './components/Cart'
import { Confirmation } from './components/Confirmation'
import { MenuSection } from './components/MenuSection'
import { OrderForm } from './components/OrderForm'
import { CATEGORY_LABELS, MENU_ITEMS } from './data/menu'
import { useCart } from './hooks/useCart'
import type { ConfirmedOrder } from './types'

type AppScreen = 'menu' | 'checkout' | 'confirmation'

export default function App() {
  const cart = useCart()
  const [screen, setScreen] = useState<AppScreen>('menu')
  const [confirmedOrder, setConfirmedOrder] = useState<ConfirmedOrder | null>(null)

  const categories = Object.keys(CATEGORY_LABELS) as Array<keyof typeof CATEGORY_LABELS>

  function handleConfirm(order: ConfirmedOrder) {
    setConfirmedOrder(order)
    cart.clearCart()
    setScreen('confirmation')
  }

  function handleNewOrder() {
    setConfirmedOrder(null)
    setScreen('menu')
  }

  if (screen === 'confirmation' && confirmedOrder) {
    return (
      <div className="app-root" data-testid="app-root">
        <header className="app-header" data-testid="app-header">
          <h1 className="app-title">Brew &amp; Go</h1>
        </header>
        <main className="app-main" data-testid="app-main">
          <Confirmation order={confirmedOrder} onNewOrder={handleNewOrder} />
        </main>
      </div>
    )
  }

  if (screen === 'checkout') {
    return (
      <div className="app-root" data-testid="app-root">
        <header className="app-header" data-testid="app-header">
          <h1 className="app-title">Brew &amp; Go</h1>
        </header>
        <main className="app-main" data-testid="app-main">
          <OrderForm
            lines={cart.lines}
            onConfirm={handleConfirm}
            onBack={() => setScreen('menu')}
          />
        </main>
      </div>
    )
  }

  return (
    <div className="app-root" data-testid="app-root">
      <header className="app-header" data-testid="app-header">
        <h1 className="app-title">Brew &amp; Go</h1>
      </header>
      <main className="app-main app-main--split" data-testid="app-main">
        <div className="menu-panel" data-testid="menu-panel">
          {categories.map((cat) => (
            <MenuSection
              key={cat}
              category={cat}
              label={CATEGORY_LABELS[cat]}
              items={MENU_ITEMS}
              onAdd={cart.addItem}
            />
          ))}
        </div>
        <Cart
          lines={cart.lines}
          cart={cart}
          onCheckout={() => setScreen('checkout')}
        />
      </main>
    </div>
  )
}
