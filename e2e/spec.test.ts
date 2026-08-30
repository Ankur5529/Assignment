import { test, expect } from '@playwright/test'

const BASE = 'http://localhost:5173'

// =============================================================================
// R1 — Empty cart shows exactly "Your cart is empty"; checkout disabled
// =============================================================================
test('R1 — empty cart shows exact message and checkout is disabled', async ({ page }) => {
  await page.goto(BASE)

  // On a fresh load (or after clearing localStorage) the cart should be empty
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  const emptyMsg = page.getByTestId('cart-empty-message')
  await expect(emptyMsg).toBeVisible()
  await expect(emptyMsg).toHaveText('Your cart is empty')

  // Checkout button must not be visible when cart is empty
  const checkoutBtn = page.getByTestId('checkout-btn')
  await expect(checkoutBtn).not.toBeVisible()
})

// =============================================================================
// R2 — Same item, identical options → increments quantity; no second line
// =============================================================================
test('R2 — same item + same options increments quantity, not a new line', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add Espresso (default: small, whole milk) twice
  const addEspresso = page.getByTestId('add-to-cart-espresso')
  await addEspresso.click()
  await addEspresso.click()

  // There should be exactly one cart line for espresso
  const lines = page.getByTestId(/^cart-line-espresso/)
  await expect(lines).toHaveCount(1)

  // Quantity should be 2
  const qty = page.getByTestId(/^quantity-espresso/)
  await expect(qty).toHaveText('2')
})

// =============================================================================
// R3 — Same item, different options → separate line
// =============================================================================
test('R3 — same item with different options creates a separate cart line', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add Latte with Small / Whole
  await page.getByTestId('size-small-latte').click()
  await page.getByTestId('milk-whole-latte').click()
  await page.getByTestId('add-to-cart-latte').click()

  // Add Latte with Medium / Oat (different options)
  await page.getByTestId('size-medium-latte').click()
  await page.getByTestId('milk-oat-latte').click()
  await page.getByTestId('add-to-cart-latte').click()

  // Should be 2 distinct cart lines
  const lines = page.getByTestId(/^cart-line-latte/)
  await expect(lines).toHaveCount(2)
})

// =============================================================================
// R4 — Quantity never below 1; decrementing at 1 removes the line
// =============================================================================
test('R4 — decrementing at quantity 1 removes the line', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add one Espresso
  await page.getByTestId('add-to-cart-espresso').click()

  // Find the decrement button for the espresso line
  const decrementBtn = page.getByTestId(/^decrement-espresso/)
  await expect(decrementBtn).toBeVisible()

  // Decrement once — line should disappear (quantity was 1)
  await decrementBtn.click()

  const lines = page.getByTestId(/^cart-line-espresso/)
  await expect(lines).toHaveCount(0)

  // Cart should show empty message
  await expect(page.getByTestId('cart-empty-message')).toBeVisible()
})

// =============================================================================
// R5 — Subtotal, tax (8%), and total computed and displayed per money rules
// =============================================================================
test('R5 — subtotal, tax, and total computed correctly with integer cents', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add one Latte ($4.50) with default Small / Whole options
  await page.getByTestId('size-small-latte').click()
  await page.getByTestId('add-to-cart-latte').click()

  // Subtotal = 450 cents = $4.50
  await expect(page.getByTestId('subtotal-value')).toHaveText('$4.50')

  // Tax = Math.round(450 * 0.08) = Math.round(36) = 36 cents = $0.36
  await expect(page.getByTestId('tax-value')).toHaveText('$0.36')

  // Total = 450 + 36 = 486 cents = $4.86
  await expect(page.getByTestId('total-value')).toHaveText('$4.86')
})

test('R5 — display always uses exactly two decimal places ($4.50, never $4.5)', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add Latte ($4.50)
  await page.getByTestId('add-to-cart-latte').click()

  const subtotal = await page.getByTestId('subtotal-value').textContent()
  // Must match $X.XX format — never $X.X
  expect(subtotal).toMatch(/^\$\d+\.\d{2}$/)
  expect(subtotal).toBe('$4.50')  // Not "$4.5"
})

// =============================================================================
// R6 — Checkout requires non-empty name and exactly 10 phone digits
// =============================================================================
test('R6 — submit is disabled until name is non-empty and phone has exactly 10 digits', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add an item to enable checkout flow
  await page.getByTestId('add-to-cart-espresso').click()
  await page.getByTestId('checkout-btn').click()

  const submitBtn = page.getByTestId('submit-order-btn')

  // Initially disabled (both fields empty)
  await expect(submitBtn).toBeDisabled()

  // Name only → still disabled
  await page.getByTestId('input-name').fill('Alice')
  await expect(submitBtn).toBeDisabled()

  // Name + 9 digits → still disabled
  await page.getByTestId('input-phone').fill('512345678')
  await expect(submitBtn).toBeDisabled()

  // Name + 10 digits → enabled
  await page.getByTestId('input-phone').fill('5123456789')
  await expect(submitBtn).toBeEnabled()

  // Name + 11 digits → disabled again (too many digits)
  await page.getByTestId('input-phone').fill('51234567890')
  await expect(submitBtn).toBeDisabled()
})

// =============================================================================
// R7 — Confirmation shows order number /^ORD-\d{6}$/, itemized list, matching total
// =============================================================================
test('R7 — confirmation shows valid order number, itemized lines, and matching total', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add Cappuccino (Small = $4.00)
  await page.getByTestId('size-small-cappuccino').click()
  await page.getByTestId('add-to-cart-cappuccino').click()

  // Checkout
  await page.getByTestId('checkout-btn').click()
  await page.getByTestId('input-name').fill('Bob')
  await page.getByTestId('input-phone').fill('5551234567')
  await page.getByTestId('submit-order-btn').click()

  // Confirmation screen
  await expect(page.getByTestId('confirmation-screen')).toBeVisible()

  // "Order confirmed" heading (exact string from spec)
  await expect(page.getByTestId('confirmation-heading')).toHaveText('Order confirmed')

  // Order number matches /^ORD-\d{6}$/
  const orderNumber = await page.getByTestId('order-number').textContent()
  expect(orderNumber?.trim()).toMatch(/^ORD-\d{6}$/)

  // Itemized lines visible
  const lines = page.getByTestId(/^confirmation-line-/)
  await expect(lines).toHaveCount(1)

  // Total on confirmation matches cart total
  const confTotal = await page.getByTestId('conf-total-value').textContent()
  // Subtotal=400, Tax=Math.round(400*0.08)=32, Total=432 = $4.32
  expect(confTotal?.trim()).toBe('$4.32')
})

// =============================================================================
// R8 — Cart survives a page reload (localStorage persistence)
// =============================================================================
test('R8 — cart persists across page reload including options and quantities', async ({ page }) => {
  await page.goto(BASE)
  await page.evaluate(() => localStorage.removeItem('coffee-cart-v1'))
  await page.reload()

  // Add 2 × Latte Medium/Oat
  await page.getByTestId('size-medium-latte').click()
  await page.getByTestId('milk-oat-latte').click()
  await page.getByTestId('add-to-cart-latte').click()
  await page.getByTestId('add-to-cart-latte').click()

  // Add 1 × Butter Croissant (no size/milk options)
  await page.getByTestId('add-to-cart-butter-croissant').click()

  // Verify 2 lines in cart
  let lines = page.getByTestId(/^cart-line-/)
  await expect(lines).toHaveCount(2)

  // Reload the page
  await page.reload()

  // Cart lines must survive reload
  lines = page.getByTestId(/^cart-line-/)
  await expect(lines).toHaveCount(2)

  // Latte quantity must be 2
  const latteQty = page.getByTestId(/^quantity-latte/)
  await expect(latteQty).toHaveText('2')

  // Croissant quantity must be 1
  const croissantQty = page.getByTestId(/^quantity-butter-croissant/)
  await expect(croissantQty).toHaveText('1')
})
