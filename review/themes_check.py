from playwright.sync_api import sync_playwright
from pathlib import Path
import json
out=Path('/workspace/vetdosis_pro/review')
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 page=b.new_page(viewport={'width':390,'height':844})
 errors=[]
 page.on('pageerror',lambda err:errors.append(str(err)))
 page.goto('http://127.0.0.1:8080',wait_until='networkidle');page.wait_for_timeout(1000)
 page.mouse.click(370,28);page.wait_for_timeout(300)
 for mode,y in [('claro',432),('oscuro',480)]:
  page.mouse.click(340,384);page.wait_for_timeout(250)
  page.mouse.click(60,432);page.wait_for_timeout(400)
  for name,x,y in [('esmeralda',80,273),('oceano',210,273),('indigo',320,273),('ambar',70,319),('obsidiana',190,319)]:
   page.mouse.click(x,y);page.wait_for_timeout(350)
   page.screenshot(path=str(out/f'tema-{name}-{mode}.png'))
 page.reload(wait_until='networkidle');page.wait_for_timeout(800)
 page.mouse.click(370,28);page.wait_for_timeout(300)
 page.screenshot(path=str(out/'apariencia-guardada.png'))
 page.mouse.click(28,28);page.wait_for_timeout(350)
 page.screenshot(path=str(out/'menu-celular.png'))
 (out/'browser-errors.json').write_text(json.dumps(errors))
 assert not errors,errors
 print('10 variantes capturadas, apariencia tras recarga y menú. Sin errores JS.')
 b.close()
