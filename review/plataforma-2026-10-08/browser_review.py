"""Local synthetic preview only; no Supabase, account or provider calls."""
from pathlib import Path
from urllib.parse import urlencode
import json
from playwright.sync_api import sync_playwright
out=Path(__file__).parent
checks=[];errors=[];console_errors=[]
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox'])
 for size in [(390,844),(1440,1000)]:
  for screen in ['Inicio','Ajustes','Producto y costos','Inicio guiado','Asistente IA','Planes']:
   for theme in ['light','dark']:
    page=browser.new_page(viewport={'width':size[0],'height':size[1]})
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda msg:console_errors.append(msg.text) if msg.type=='error' else None)
    response=page.goto('http://127.0.0.1:8082/?'+urlencode({'screen':screen,'theme':theme}),wait_until='networkidle')
    page.wait_for_selector('flutter-view',timeout=30000)
    page.wait_for_timeout(500)
    slug={'Inicio':'inicio','Ajustes':'ajustes','Producto y costos':'producto','Inicio guiado':'guia','Asistente IA':'ia','Planes':'planes'}[screen]
    name=f'{slug}-{size[0]}-{theme}.png'
    page.screenshot(path=str(out/name))
    checks.append({'screen':screen,'width':size[0],'theme':theme,'http':response.status,'screenshot':name})
    if screen in ['Ajustes','Producto y costos','Asistente IA','Inicio guiado']:
     page.mouse.move(size[0]//2,size[1]//2);page.mouse.wheel(0,5000);page.wait_for_timeout(200)
     page.screenshot(path=str(out/name.replace('.png','-inferior.png')))
    if screen=='Inicio':
     page.mouse.click(25,28);page.wait_for_timeout(200);page.screenshot(path=str(out/name.replace('inicio-','menu-')))
    page.close()
 (out/'browser-results.json').write_text(json.dumps({'synthetic_preview':True,'checks':checks,'page_errors':errors,'console_errors':console_errors},ensure_ascii=False,indent=2))
 browser.close()
assert not errors,errors
assert not console_errors,console_errors
print(f'{len(checks)} capturas locales; sin errores JS de página.')
