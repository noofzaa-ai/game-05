"""PWA (Add to Home Screen) checks for the web build. python -X utf8 -m unittest tests.test_web_pwa  (or discover -p test_web_pwa.py).
No Godot needed: it runs build_web.write_pwa into a temp dir and reads the template and nginx config."""
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'pipeline'))
import build_web  # noqa: E402


class WebPwa(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.stage = Path(cls.tmp.name)
        if not hasattr(build_web, 'write_pwa'):
            raise AssertionError('build_web.write_pwa missing: the build does not produce PWA files')
        build_web.write_pwa(cls.stage, 'abc123def456')
        cls.template = (ROOT / 'tools/web/play_template.html').read_text(encoding='utf-8-sig')
        cls.nginx = (ROOT / 'pipeline/nginx-web.conf').read_text()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_manifest(self):
        m = json.loads((self.stage / 'manifest.webmanifest').read_text(encoding='utf-8'))
        for key in ('name', 'short_name', 'start_url', 'scope', 'display', 'icons', 'background_color', 'theme_color'):
            self.assertIn(key, m)
        self.assertEqual(m['name'], 'ZORX')
        self.assertEqual(m['display'], 'fullscreen')
        self.assertEqual(m['display_override'][:2], ['fullscreen', 'standalone'])
        self.assertEqual(m['orientation'], 'landscape')
        self.assertEqual(m['scope'], '/')
        self.assertTrue(m['start_url'].startswith('/'))
        sizes = set()
        purposes = set()
        for icon in m['icons']:
            path = self.stage / icon['src']
            self.assertTrue(path.is_file(), icon['src'])
            from PIL import Image
            w, h = Image.open(path).size
            self.assertEqual('%dx%d' % (w, h), icon['sizes'])
            self.assertLess(path.stat().st_size, 200 * 1024, icon['src'] + ' too big')
            sizes.add(w)
            purposes.add(icon.get('purpose', 'any'))
        self.assertTrue({192, 512} <= sizes)
        self.assertIn('maskable', purposes)
        from PIL import Image
        self.assertEqual(Image.open(self.stage / 'apple-touch-icon.png').size, (180, 180))

    def test_page_tags(self):
        t = self.template
        self.assertIn('<link rel="manifest" href="manifest.webmanifest">', t)
        for needle in ('apple-mobile-web-app-capable', 'mobile-web-app-capable', 'apple-mobile-web-app-title',
                       'black-translucent', 'rel="apple-touch-icon"', 'name="theme-color"', 'viewport-fit=cover',
                       'safe-area-inset-left', "register('sw.js'", 'nosw=1'):
            self.assertIn(needle, t, needle)
        self.assertNotIn('user-scalable=no', t)  # accessibility: pinch zoom stays available

    def test_service_worker_never_caches_the_game(self):
        sw = (self.stage / 'sw.js').read_text(encoding='utf-8')
        self.assertIn('abc123def456', sw)
        self.assertNotIn('__BUILD_ID__', sw)
        shell = re.search(r'const SHELL = \[(.*?)\];', sw, re.S).group(1)
        for banned in ('play.html', 'packs.json', 'wasm', '.pck', 'index.js', "'/'"):
            self.assertNotIn(banned, shell, banned)
        self.assertNotIn('cache.addAll', sw)
        self.assertNotIn('cache.put(event.request', sw)  # no runtime caching of arbitrary requests
        self.assertIn("mode !== 'navigate'", sw)

    def test_nginx_headers(self):
        n = self.nginx
        manifest = re.search(r'location = /manifest\.webmanifest \{(.*?try_files)', n, re.S)
        self.assertTrue(manifest)
        self.assertIn('application/manifest+json', manifest.group(1))
        self.assertIn('no-cache', manifest.group(1))
        sw = re.search(r'location = /sw\.js \{(.*?try_files)', n, re.S)
        self.assertTrue(sw)
        self.assertIn('Service-Worker-Allowed "/"', sw.group(1))
        self.assertIn('no-cache', sw.group(1))
        self.assertRegex(n, r'apple-touch-icon')


if __name__ == '__main__':
    unittest.main()
