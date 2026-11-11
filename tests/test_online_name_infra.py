import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('name_deploy', Path(__file__).resolve().parents[1] / 'server/names/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class OnlineNameInfraTests(unittest.TestCase):
    def docs(self):
        return deploy.render('registry.example/validator@sha256:' + 'a'*64, 'registry.example/nakama@sha256:' + 'b'*64, 'unit-token-'*4)

    def test_no_original_secret_or_database_resource(self):
        documents = self.docs()
        self.assertEqual([(d['kind'],d['metadata']['name']) for d in documents if d['kind']=='Secret'], [('Secret',deploy.SECRET)])
        self.assertFalse(any(d['kind']=='StatefulSet' for d in documents))
        self.assertNotIn('postgres-auth', json.dumps(documents))

    def test_private_worker_has_no_public_route_and_no_egress(self):
        documents = self.docs()
        service = next(d for d in documents if d['kind']=='Service')
        self.assertEqual(service['spec']['type'],'ClusterIP')
        policy = next(d for d in documents if d['kind']=='NetworkPolicy')['spec']
        self.assertEqual(policy['egress'],[])
        self.assertEqual(policy['ingress'][0]['from'],[{'podSelector':{'matchLabels':{'app':'nakama'}}}])

    def test_nakama_uses_second_config_and_immutable_image(self):
        nk = self.docs()[-1]['spec']['template']['spec']['containers'][0]
        self.assertEqual(nk['args'],['--config','/run/nakama/config.yml','--config','/run/zorx-names/runtime.yml'])
        self.assertIn('@sha256:',nk['image'])

    def test_new_token_restarts_both_services(self):
        first = self.docs()
        second = deploy.render('x@sha256:'+'a'*64,'y@sha256:'+'b'*64,'different-token-'*3)
        for d in first:
            if d['kind']=='Deployment':
                other = next(x for x in second if x['kind']=='Deployment' and x['metadata']['name']==d['metadata']['name'])
                self.assertNotEqual(d['spec']['template']['metadata']['annotations'],other['spec']['template']['metadata']['annotations'])

    def test_unpinned_images_are_rejected(self):
        with self.assertRaises(ValueError):
            deploy.render('validator:latest','nakama:latest','unit-token-'*4)


class ProfileWorkerPackageTests(unittest.TestCase):
    def test_minimal_worker_contains_rules_and_profile_data_without_art_or_secrets(self):
        import tempfile
        spec = importlib.util.spec_from_file_location('worker_package', Path(__file__).resolve().parents[1] / 'server/names/smoke_worker.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            builder.prepare(root)
            for path in ('server/profile/runner.gd', 'logic/commands.gd', 'data/items/catalog.json', 'data/items/rules.json', 'data/camp/camp.json', 'data/cosmetics/faces.json'):
                self.assertTrue((root / path).is_file(), path)
            for path in ('build', 'art', 'client', 'server/k3s', 'data/online.local.json'):
                self.assertFalse((root / path).exists(), path)

    def test_runtime_includes_profile_bridge_and_build_never_pushes(self):
        root = Path(__file__).resolve().parents[1]
        config = json.loads((root / 'server/names/runtime/tsconfig.json').read_text())
        self.assertIn('src/profile.ts', config['files'])
        builder = (root / 'server/names/build_images.py').read_text()
        self.assertNotIn("'push'", builder)
        self.assertIn("'server/profile'", builder)


class RpcSecurityConfigurationTests(unittest.TestCase):
    def test_production_limits_are_explicit_and_worker_stays_private(self):
        docs = deploy.render('x@sha256:'+'a'*64, 'y@sha256:'+'b'*64, 'unit-token-'*4)
        env = json.loads(docs[0]['stringData']['runtime.yml'])['runtime']['env']
        self.assertIn('ZORX_RPC_BURST=20', env)
        self.assertIn('ZORX_RPC_REFILL=5', env)
        self.assertIn('ZORX_RPC_AUDIT_THRESHOLD=8', env)
        self.assertNotIn('ZORX_RPC_BURST=1000', env)
