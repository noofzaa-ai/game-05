"""Offline infrastructure unit tests: python3 -m unittest discover -s tests -p test_online_infra.py"""
import importlib.util
import contextlib
import io
import json
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

render = module('render', 'server/k3s/render.py')
secrets = module('prepare', 'server/k3s/prepare_secrets.py')
sys.path.insert(0,str(ROOT/'server/k3s'))
restore_job = module('restore_job','server/k3s/restore_job.py')
standalone = module('standalone','server/k3s/standalone.py')
tunnel_ingress = module('tunnel_ingress','server/k3s/tunnel_ingress.py')
backup = module('backup', 'server/backup/backup.py')


class Infrastructure(unittest.TestCase):
    def test_namespaces_are_disjoint(self):
        for environment in ('staging', 'prod'):
            docs = render.render(environment)['items']
            self.assertEqual(docs[0]['metadata']['name'], 'zorx-' + environment)
            self.assertTrue(all(doc['metadata']['namespace'] == 'zorx-' + environment for doc in docs[1:]))
            self.assertFalse(any(doc['kind'] == 'Secret' for doc in docs))

    def test_no_default_public_exposure(self):
        docs = render.render('staging')['items']
        self.assertFalse(any(doc['kind'] == 'Ingress' for doc in docs))
        for doc in docs:
            if doc['kind'] == 'Service':
                self.assertNotIn(doc['spec'].get('type'), ('NodePort', 'LoadBalancer'))
                self.assertNotIn(7351, [p['port'] for p in doc['spec']['ports']])

    def test_tls_requires_explicit_gateway_choices(self):
        for args in ({'host':'game.example.com'}, {'host':'http://example.com', 'ingress_class':'traefik', 'tls_secret':'cert'}):
            with self.assertRaises(ValueError): render.render('prod', **args)
        doc = render.render('prod','game.example.com','traefik','cert')['items'][-1]
        self.assertEqual(doc['spec']['tls'], [{'hosts':['game.example.com'],'secretName':'cert'}])
        self.assertEqual(doc['spec']['rules'][0]['http']['paths'][0]['backend']['service']['port']['number'],7350)

    def test_pinned_images_and_restricted_workloads(self):
        for doc in render.render('staging')['items']:
            if doc['kind'] in ('Deployment','StatefulSet'):
                pod = doc['spec']['template']['spec']
                self.assertFalse(pod['automountServiceAccountToken'])
                self.assertTrue(pod['securityContext']['runAsNonRoot'])
                for container in pod['containers'] + pod.get('initContainers',[]):
                    self.assertIn('@sha256:',container['image'])
                    self.assertIn('limits',container['resources'])
                    self.assertFalse(container['securityContext']['allowPrivilegeEscalation'])

    def test_backup_opt_in_and_suspended(self):
        self.assertFalse(any(d['kind']=='CronJob' for d in render.render('staging')['items']))
        with self.assertRaises(ValueError): render.render('staging',backup_image='backup:latest')
        cron = render.render('staging',backup_image='registry/backup@sha256:'+'a'*64)['items'][-1]
        self.assertTrue(cron['spec']['suspend'])
        self.assertEqual(cron['spec']['concurrencyPolicy'],'Forbid')
        self.assertEqual(cron['spec']['timeZone'],'Etc/UTC')

    def test_secrets_unique_and_consistent(self):
        first, second = secrets.generate('staging'), secrets.generate('prod')
        app = json.loads(first[1]['stringData']['config.yml'])
        self.assertIn(first[0]['stringData']['app-password'], app['database']['address'][0])
        self.assertEqual(app['console']['address'],'127.0.0.1')
        self.assertNotEqual(first[0]['stringData']['admin-password'], first[0]['stringData']['app-password'])
        self.assertNotEqual(app['socket']['server_key'],json.loads(second[1]['stringData']['config.yml'])['socket']['server_key'])

    def test_private_secret_files_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'private'
            command=[sys.executable,str(ROOT/'server/k3s/prepare_secrets.py'),'--environment','staging','--output-dir',str(target)]
            result=subprocess.run(command,capture_output=True,text=True,check=True)
            self.assertEqual(target.stat().st_mode & 0o777,0o700)
            for path in target.iterdir():
                self.assertEqual(path.stat().st_mode & 0o777,0o600)
                payload=json.loads(path.read_text())
                self.assertNotIn(next(iter(payload['stringData'].values())),result.stdout)
            old=(target/'postgres-auth.json').read_bytes()
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
            self.assertEqual(old,(target/'postgres-auth.json').read_bytes())

    def test_restore_job_is_scratch_only_and_isolated(self):
        image='registry/backup@sha256:'+'a'*64
        for database in ('nakama','postgres','restore_bad-name'):
            with self.assertRaises(ValueError): restore_job.restore_job('staging',image,'zorx-staging/a.dump',database,'restore-test')
        with self.assertRaises(ValueError): restore_job.restore_job('staging',image,'zorx-prod/a.dump','restore_check','restore-test')
        job=restore_job.restore_job('staging',image,'zorx-staging/a.dump','restore_check','restore-test')
        self.assertEqual(job['metadata']['namespace'],'zorx-staging')
        pod=job['spec']['template']
        self.assertEqual(pod['metadata']['labels']['app'],'postgres-backup')
        self.assertEqual(pod['spec']['containers'][0]['args'],['restore','--key','zorx-staging/a.dump','--target-db','restore_check'])

    def test_restore_verifies_before_one_transaction(self):
        payload=b'archive fixture'
        import hashlib
        class S3:
            def head_object(self,**kwargs): return {'ContentLength':len(payload),'Metadata':{'sha256':hashlib.sha256(payload).hexdigest()}}
            def download_file(self,bucket,key,path): Path(path).write_bytes(payload)
        with tempfile.TemporaryDirectory() as directory, patch.object(backup.subprocess,'run') as commands, contextlib.redirect_stdout(io.StringIO()):
            backup.restore(S3(),'b','k','restore_test',directory)
            args=commands.call_args_list[-1].args[0]
            self.assertIn('--single-transaction',args)
            self.assertEqual(args[args.index('--dbname')+1],'restore_test')

    def test_remote_manifest_is_self_contained_and_uses_host_path(self):
        documents=standalone.bundle()
        self.assertNotIn("/Users/",json.dumps(documents))
        self.assertEqual(len([d for d in documents if d['kind']=='Secret']),2)
        db=next(d for d in documents if d['kind']=='StatefulSet')
        self.assertNotIn('volumeClaimTemplates',db['spec'])
        pod=db['spec']['template']['spec']
        self.assertEqual(next(v for v in pod['volumes'] if v['name']=='data')['hostPath']['path'],'/data/k3s/volumes/zorx-game/postgres-staging')
        self.assertEqual(pod['securityContext']['runAsUser'],70)
        self.assertEqual(pod['initContainers'][0]['securityContext']['runAsUser'],0)
        self.assertNotIn('-R',pod['initContainers'][0]['command'][-1])
        service=next(d for d in documents if d['kind']=='Service' and d['metadata']['name']=='nakama')
        self.assertEqual(service['spec']['type'],'ClusterIP')
        self.assertNotIn('nodePort',service['spec']['ports'][0])
        self.assertNotIn('externalTrafficPolicy',service['spec'])

    def test_remote_versioned_yaml_matches_builder_and_has_no_secrets(self):
        import yaml
        saved=list(yaml.safe_load_all((ROOT/'server/k3s/deployment.yaml').read_text()))
        self.assertEqual(saved,standalone.resources())
        self.assertFalse(any(d['kind']=='Secret' for d in saved))

    def test_tunnel_overlay_preserves_restrictions_and_traefik_and_selector(self):
        policy,ingress=tunnel_ingress.overlay()
        peer=policy['spec']['ingress'][0]['from'][-1]
        self.assertIn('namespaceSelector',peer)
        self.assertIn('podSelector',peer)
        self.assertEqual(peer['namespaceSelector']['matchLabels']['kubernetes.io/metadata.name'],'kube-system')
        self.assertEqual(policy['spec']['ingress'][0]['ports'],[{'protocol':'TCP','port':7350}])
        self.assertEqual(ingress['spec']['rules'][0]['host'],'zorxapi.daiyooo.com')
        self.assertEqual(ingress['spec']['rules'][0]['http']['paths'][0]['backend']['service']['port']['number'],7350)
        self.assertNotIn('tls',ingress['spec'])
        self.assertEqual(ingress['metadata']['annotations']['traefik.ingress.kubernetes.io/router.entrypoints'],'web')

    def test_tunnel_yaml_is_generated_and_contains_only_overlay(self):
        import yaml
        documents=list(yaml.safe_load_all((ROOT/'server/k3s/ingress.yaml').read_text()))
        self.assertEqual(documents,tunnel_ingress.overlay())
        self.assertEqual([d['kind'] for d in documents],['NetworkPolicy','Ingress'])
        for host in ('https://api.example.com','a/b','*'):
            with self.assertRaises(ValueError):tunnel_ingress.overlay(host)

    def test_backup_verifies_size_and_metadata(self):
        class S3:
            def upload_file(self,path,bucket,key,ExtraArgs):
                self.data=Path(path).read_bytes(); self.extra=ExtraArgs
            def head_object(self,**kwargs):
                return {'ContentLength':len(self.data),'Metadata':self.extra['Metadata']}
        def command(args,**kwargs):
            if args[0]=='pg_dump': Path(args[-1]).write_bytes(b'archive fixture')
        with tempfile.TemporaryDirectory() as directory, patch.object(backup.subprocess,'run',side_effect=command):
            s3=S3()
            key=backup.backup(s3,'private-bucket','zorx-staging/',directory)
            self.assertTrue(key.startswith('zorx-staging/'))
            self.assertEqual(s3.extra['ServerSideEncryption'],'AES256')

    def test_restore_rejects_primary_or_corrupt_backup(self):
        class S3:
            def head_object(self,**kwargs): return {'ContentLength':3,'Metadata':{'sha256':'a'*64}}
            def download_file(self,bucket,key,path): Path(path).write_bytes(b'bad')
        with tempfile.TemporaryDirectory() as directory, patch.object(backup.subprocess,'run') as commands:
            with self.assertRaises(ValueError): backup.restore(S3(),'b','k','nakama',directory)
            with self.assertRaises(ValueError): backup.restore(S3(),'b','k','restore_check',directory)
            commands.assert_not_called()


if __name__ == '__main__': unittest.main()
