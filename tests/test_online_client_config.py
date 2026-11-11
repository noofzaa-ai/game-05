import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('online_client_config', Path(__file__).resolve().parents[1] / 'pipeline/online_client_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class PublicClientConfigTests(unittest.TestCase):
    def test_only_public_socket_key_copied(self):
        private = {'socket': {'server_key': 'public-app-key'}, 'session': {'encryption_key': 'PRIVATE-SESSION'}, 'runtime': {'http_key': 'PRIVATE-RUNTIME'}, 'database': {'address': ['PRIVATE-DB']}}
        docs = [{'kind': 'Secret', 'metadata': {'name': 'nakama-config'}, 'stringData': {'config.yml': json.dumps(private)}}]
        result = config.public_config(docs, 'api.example.com')
        self.assertEqual(result['client_key'], 'public-app-key')
        self.assertNotIn('PRIVATE-', json.dumps(result))
        self.assertEqual(set(result), {'version', 'enabled', 'host', 'port', 'scheme', 'client_key'})

    def test_no_url_in_host(self):
        docs = [{'kind': 'Secret', 'metadata': {'name': 'nakama-config'}, 'stringData': {'config.yml': '{"socket":{"server_key":"app"}}'}}]
        with self.assertRaises(ValueError):
            config.public_config(docs, 'https://user:password@example.com')

    def test_web_export_excludes_private_development_directories(self):
        import configparser
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(Path(__file__).resolve().parents[1] / 'export_presets.cfg')
        excluded = parser['preset.0']['exclude_filter']
        for folder in ('build/*', 'server/*', 'pipeline/*', 'docs/*', 'tools/*', 'tests/*'):
            self.assertIn(folder, excluded)
