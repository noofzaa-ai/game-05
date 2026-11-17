#!/usr/bin/env python3
"""Compose the PWA icons from EXISTING loading-screen art only (valley backdrop + title ribbon + the page's own
Taviraj wordmark font). No new art: a layout of existing pieces, rendered once with Chrome (Playwright).
Output: tools/web/pwa/icon-192.png, icon-512.png, icon-maskable-512.png, apple-touch-icon.png (180).
Run: python tools/web/make_pwa_icons.py   (commit the PNGs; build_web.py only copies them)."""
import base64
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tools/web/pwa'


def uri(path, mime):
    return f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode()


def page(ribbon_width_pct):
    bg = uri(ROOT / 'tools/web/static/loading_valley.webp', 'image/webp')
    rib = uri(ROOT / 'tools/web/static/loading_title.webp', 'image/webp')
    font = uri(ROOT / 'art/fonts/Taviraj-SemiBold.woff2', 'font/woff2')
    return f'''<style>@font-face{{font-family:T;src:url({font});font-weight:600 800}}
html,body{{margin:0;width:512px;height:512px;overflow:hidden}}
#i{{position:relative;width:512px;height:512px;background:#1b2333 url({bg}) 38% 50%/auto 100% no-repeat}}
#i::after{{content:"";position:absolute;inset:0;background:radial-gradient(ellipse at 50% 50%,#0000 35%,#05060bb0 100%)}}
#r{{position:absolute;z-index:1;left:50%;top:50%;width:{ribbon_width_pct}%;aspect-ratio:640/181;transform:translate(-50%,-50%);
background:url({rib}) center/100% 100% no-repeat;filter:drop-shadow(0 8px 14px #000a)}}
#r span{{position:absolute;inset:0 0 38% 0;display:grid;place-items:center;font:800 {ribbon_width_pct*5.12*0.2:.1f}px/1 T,serif;letter-spacing:.1em;text-indent:.1em;color:#3A2414;text-shadow:0 1px 0 #fff6e0}}
</style><div id=i><div id=r><span>ZORX</span></div></div>'''


def main():
    OUT.mkdir(exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome')
        for name, width, size in (('icon-512', 86, 512), ('icon-192', 86, 192), ('icon-maskable-512', 60, 512),
                                  ('apple-touch-icon', 76, 180)):
            context = browser.new_context(viewport={'width': 512, 'height': 512}, device_scale_factor=size / 512)
            tab = context.new_page()
            tab.set_content(page(width))
            tab.evaluate('document.fonts.ready')
            tab.wait_for_timeout(300)
            tab.locator('#i').screenshot(path=str(OUT / (name + '.png')))
            context.close()
        browser.close()
    from PIL import Image
    for f in OUT.glob('*.png'):  # 128-colour palette: the art is flat enough, keeps each icon small
        Image.open(f).convert('RGB').quantize(128, dither=Image.Dither.FLOYDSTEINBERG).save(f, optimize=True)


if __name__ == '__main__':
    main()
