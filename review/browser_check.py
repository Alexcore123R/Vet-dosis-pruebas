from playwright.sync_api import sync_playwright
from pathlib import Path
import json
out=Path('/workspace/vetdosis_pro/review')
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':390,'height':844},device_scale_factor=1)
    errors=[]
    page.on('pageerror',lambda err:errors.append(str(err)))
    page.goto('http://127.0.0.1:8080',wait_until='networkidle')
    page.wait_for_selector('flutter-view')
    page.wait_for_timeout(2000)
    page.screenshot(path=str(out/'inicio-celular.png'))
    page.evaluate("document.querySelector('flt-glass-pane')?.shadowRoot?.querySelector('flt-semantics-placeholder')?.click()")
    print(page.locator('body').inner_text()[:2000])
    page.set_viewport_size({'width':1440,'height':1000})
    page.wait_for_timeout(1000)
    page.screenshot(path=str(out/'inicio-computadora.png'))
    (out/'browser-errors.json').write_text(json.dumps(errors))
    print('Errors:',errors)
    browser.close()
