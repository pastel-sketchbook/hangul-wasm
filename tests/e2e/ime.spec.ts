import { expect, test } from '@playwright/test'

test.describe('Hangul IME Integration', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/')
    // Wait for WASM to load
    await page.waitForSelector('#status.success', { timeout: 10000 })
  })

  test('page loads successfully with WASM', async ({ page }) => {
    const status = page.locator('#status')
    await expect(status).toHaveClass(/success/)
    await expect(status).toContainText('loaded')
  })

  test('can enable Korean IME', async ({ page }) => {
    const toggle = page.locator('#imeToggle2')
    await toggle.click()
    await expect(toggle).toContainText('Disable')
  })

  test('2-Bulsik: types 한글 correctly', async ({ page }) => {
    // Enable IME
    await page.locator('#imeToggle2').click()

    // Focus the input field
    const input = page.locator('#imeInput')
    await input.focus()

    // Type "gksrmf" which should produce "한글" in 2-Bulsik
    // g=ㅎ, k=ㅏ, s=ㄴ, r=ㄱ, m=ㅡ, f=ㄹ
    await input.pressSequentially('gksrmf', { delay: 50 })

    await expect(input).toHaveValue('한글')
  })

  test('2-Bulsik: types 안녕 correctly', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // "dkssud" = 안녕 in 2-Bulsik
    // d=ㅇ, k=ㅏ, s=ㄴ, s=ㄴ, u=ㅕ, d=ㅇ
    await input.pressSequentially('dkssud', { delay: 50 })

    await expect(input).toHaveValue('안녕')
  })

  test('2-Bulsik: space finalizes composition', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // Type "gk" (ㅎ+ㅏ = 하) then space
    await input.pressSequentially('gk', { delay: 50 })
    await input.press('Space')

    // Should be "하 "
    const value = await input.inputValue()
    expect(value).toBe('하 ')
  })

  test('2-Bulsik: backspace removes last jamo', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // Type "gks" (ㅎ+ㅏ+ㄴ = 한)
    await input.pressSequentially('gks', { delay: 50 })
    await expect(input).toHaveValue('한')

    // Backspace should remove ㄴ, leaving 하
    await input.press('Backspace')
    await expect(input).toHaveValue('하')

    // Another backspace removes ㅏ, leaving ㅎ
    await input.press('Backspace')
    await expect(input).toHaveValue('ㅎ')
  })

  test('2-Bulsik: double consonant ㄲ', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // Type "rr" which should produce ㄲ in 2-Bulsik
    await input.pressSequentially('rr', { delay: 50 })
    await expect(input).toHaveValue('ㄲ')

    // Add ㅏ to make 까
    await input.pressSequentially('k', { delay: 50 })
    await expect(input).toHaveValue('까')
  })

  test('2-Bulsik: double final consonant splitting', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // Type "ekfr" = ㄷ+ㅏ+ㄹ+ㄱ = 닭 (with double final ㄺ)
    await input.pressSequentially('ekfr', { delay: 50 })
    await expect(input).toHaveValue('닭')

    // Now type ㅏ - should split: 달 + 가
    await input.pressSequentially('k', { delay: 50 })
    await expect(input).toHaveValue('달가')
  })

  test('blur commits composition', async ({ page }) => {
    await page.locator('#imeToggle2').click()

    const input = page.locator('#imeInput')
    await input.focus()

    // Type partial syllable "gk" (하)
    await input.pressSequentially('gk', { delay: 50 })
    await expect(input).toHaveValue('하')

    // Click somewhere outside the field to trigger blur
    await page.locator('h1').click()

    // Wait a bit for blur handler
    await page.waitForTimeout(200)

    // The composition should be committed (하 stays as 하)
    await expect(input).toHaveValue('하')

    // Now focus back and type more
    await input.focus()
    await input.pressSequentially('s', { delay: 50 })

    // Since blur committed the 하, typing 's' (ㄴ) should start a new composition
    // resulting in "하ㄴ"
    await expect(input).toHaveValue('하ㄴ')
  })

  test('3-Bulsik tab is available', async ({ page }) => {
    // Click 3-Bulsik tab (Korean text: 3벌식 IME)
    const tab = page.locator('button.main-tab:has-text("3벌식")')
    await tab.click()

    // Should show 3-Bulsik content
    const content = page.locator('#tab-3bulsik')
    await expect(content).toBeVisible()
  })

  test('3-Bulsik: types 한글 correctly', async ({ page }) => {
    // Switch to 3-Bulsik tab
    await page.locator('button.main-tab:has-text("3벌식")').click()

    // Enable IME (use the 3-Bulsik toggle)
    await page.locator('#imeToggle3').click()

    const input = page.locator('#imeInput3')
    await input.focus()

    // In 3-Bulsik: m=ㅎ(초), f=ㅏ(중), s=ㄴ(종), k=ㄱ(초), g=ㅡ(중), w=ㄹ(종)
    // "한글" = ㅎ+ㅏ+ㄴ + ㄱ+ㅡ+ㄹ = mfs + kgw
    await input.pressSequentially('mfskgw', { delay: 50 })

    await expect(input).toHaveValue('한글')
  })

  test('decompose tool works', async ({ page }) => {
    // Click Tools tab
    await page.locator('button.main-tab:has-text("Tools")').click()

    // Enter a character in decompose input
    const decomposeInput = page.locator('#decomposeInput')
    await decomposeInput.fill('한')

    // Check result shows jamo
    const result = page.locator('#decomposeResult')
    await expect(result).toContainText('ㅎ')
    await expect(result).toContainText('ㅏ')
    await expect(result).toContainText('ㄴ')
  })

  test('compose tool works', async ({ page }) => {
    // Click Tools tab
    await page.locator('button.main-tab:has-text("Tools")').click()

    // The inputs already have default values (ㅎ, ㅏ, ㄴ)
    // Just click the Compose button
    await page.locator('button:has-text("Compose")').click()

    // Check result shows composed syllable
    const result = page.locator('#composeResult')
    await expect(result).toContainText('한')
  })
})
