import { chromium } from 'playwright';
import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const OUTPUT_DIR = path.join(__dirname, '../recordings');
const FRAMES_DIR = path.join(OUTPUT_DIR, 'frames');

// "한글을 입력할 수 있어요" in 2-Bulsik QWERTY
// 한 = gks, 글 = rmf, 을 = dmf, ' ', 입 = dlq, 력 = fur, 할 = gkf, ' ', 수 = tn, ' ', 있 = dlT, 어 = dj, 요 = dy
const TEXT_SEQUENCE = 'gksrmf dmf dlqfur gkf tn dlTdjdy';

async function main() {
  // Ensure output directories exist
  if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  if (fs.existsSync(FRAMES_DIR)) {
    fs.rmSync(FRAMES_DIR, { recursive: true });
  }
  fs.mkdirSync(FRAMES_DIR, { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1200, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();

  // Navigate and wait for WASM to load
  await page.goto('http://127.0.0.1:8120');
  await page.waitForSelector('#status.success', { timeout: 10000 });

  // Enable 2-Bulsik IME
  await page.locator('#imeToggle2').click();

  // Focus input
  const input = page.locator('#imeInput');
  await input.focus();

  // Get keyboard element for screenshots
  const keyboard = page.locator('#keyboard-2bulsik');

  // Capture initial frame
  let frameIndex = 0;
  await keyboard.screenshot({
    path: path.join(FRAMES_DIR, `frame_${String(frameIndex++).padStart(4, '0')}.png`),
  });

  // Type each character and capture frames
  for (const char of TEXT_SEQUENCE) {
    if (char === ' ') {
      await input.press('Space');
    } else if (char === char.toUpperCase() && char !== char.toLowerCase()) {
      // Shift + key for uppercase
      await input.press(`Shift+${char.toLowerCase()}`);
    } else {
      await input.press(char);
    }

    // Small delay for visual feedback
    await page.waitForTimeout(80);

    // Capture frame
    await keyboard.screenshot({
      path: path.join(FRAMES_DIR, `frame_${String(frameIndex++).padStart(4, '0')}.png`),
    });

    // Additional delay between keystrokes
    await page.waitForTimeout(120);
  }

  // Capture a few extra frames at the end
  for (let i = 0; i < 10; i++) {
    await page.waitForTimeout(100);
    await keyboard.screenshot({
      path: path.join(FRAMES_DIR, `frame_${String(frameIndex++).padStart(4, '0')}.png`),
    });
  }

  await browser.close();

  console.log(`Captured ${frameIndex} frames`);

  // Convert frames to GIF using ffmpeg
  const gifPath = path.join(OUTPUT_DIR, 'keyboard-demo.gif');
  try {
    execSync(
      `ffmpeg -y -framerate 8 -i "${FRAMES_DIR}/frame_%04d.png" -vf "split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" "${gifPath}"`,
      { stdio: 'inherit' }
    );
    console.log(`GIF created: ${gifPath}`);
  } catch (err) {
    console.error('Failed to create GIF with ffmpeg:', err);
  }

  // Cleanup frames
  fs.rmSync(FRAMES_DIR, { recursive: true });
}

main().catch(console.error);
