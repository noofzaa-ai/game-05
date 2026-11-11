import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('backend_smoke', Path(__file__).resolve().parents[1] / 'tools/backend/smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class BackendSmokeTests(unittest.TestCase):
    def test_post_preflight_without_allow_methods(self):
        self.assertTrue(smoke.cors_preflight({'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Authorization,Content-Type'}, 'https://game.example'))

    def test_authorization_cannot_be_wildcard(self):
        self.assertFalse(smoke.cors_preflight({'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*'}, 'https://game.example'))

    def test_header_tokens_are_exact(self):
        self.assertFalse(smoke.cors_preflight({'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'X-Authorization,Content-Type'}, 'https://game.example'))

    def test_private_state_never_overwrites(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'state.json'
            smoke.private_state(p, {'device': 'test', 'uid': 'test'})
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                smoke.private_state(p, {})

    def test_redirect_refused(self):
        self.assertIsNone(smoke.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example'))

    def test_url_rejects_credentials_and_queries(self):
        for value in ('https://user:secret@example.com', 'https://example.com/?token=secret', 'file:///tmp/test'):
            with self.assertRaises(Exception):
                smoke.valid_url(value)
        self.assertEqual(smoke.valid_url('https://example.com/'), 'https://example.com')
