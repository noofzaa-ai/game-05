import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result

class RoomInfraTests(unittest.TestCase):
    def docs(self): return load('room_deploy', 'server/rooms/deploy.py').render('example/worker@sha256:'+'a'*64)

    def test_private_service_and_policy(self):
        docs = self.docs()
        self.assertEqual(docs[1]['spec']['type'], 'ClusterIP')
        self.assertEqual(docs[2]['spec']['egress'], [])
        self.assertEqual(docs[2]['spec']['ingress'][0]['from'], [{'podSelector': {'matchLabels': {'app': 'nakama'}}}])
        self.assertFalse(any(row['kind'] in ('Secret', 'StatefulSet', 'Ingress') for row in docs))

    def test_one_cpu_nonroot_and_no_api_token(self):
        pod = self.docs()[0]['spec']['template']['spec']
        self.assertFalse(pod['automountServiceAccountToken'])
        worker = pod['containers'][0]
        self.assertEqual(worker['resources']['requests']['cpu'], '1')
        self.assertEqual(worker['resources']['limits']['cpu'], '1')
        self.assertTrue(worker['securityContext']['readOnlyRootFilesystem'])
        self.assertEqual(worker['env'][0]['valueFrom']['secretKeyRef']['name'], 'zorx-names-runtime')

    def test_mutable_images_rejected(self):
        with self.assertRaises(ValueError): load('room_deploy', 'server/rooms/deploy.py').render('example/worker:latest')

    def test_package_is_minimal_and_contains_sim_data(self):
        builder = load('room_smoke', 'server/rooms/smoke.py')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); builder.prepare(root)
            for file in ('server/rooms/worker.gd', 'server/shared/private_http.gd', 'logic/game_sim.gd', 'data/journeys/ink_road.json', 'data/combat/combat.json', 'data/maps/goblin_arena_a.json'):
                self.assertTrue((root / file).is_file(), file)
            for file in ('server/names', 'server/profile', 'client', 'art', 'build', 'data/online.local.json'):
                self.assertFalse((root / file).exists(), file)

    def test_authenticated_gameplay_route_and_narrow_egress(self):
        docs = load('room_network_deploy', 'server/rooms/deploy.py').render('example/worker@sha256:'+'a'*64, True)
        pod = docs[0]['spec']['template']['spec']['containers'][0]
        self.assertEqual([p['containerPort'] for p in pod['ports']], [8051, 8060])
        secret = next(e for e in pod['env'] if e['name'] == 'ZORX_ROOM_HTTP_KEY')
        self.assertEqual(secret['valueFrom']['secretKeyRef'], {'name':'zorx-room-server','key':'http_key'})
        rule = docs[-1]['spec']['rules'][0]
        self.assertEqual(rule['host'], 'zorxapi.daiyooo.com')
        self.assertEqual(rule['http']['paths'][0]['path'], '/room')
        egress = docs[2]['spec']['egress']
        self.assertEqual(egress[0]['ports'], [{'protocol':'TCP','port':7350}])
        self.assertEqual(egress[1]['ports'], [{'protocol':'UDP','port':53},{'protocol':'TCP','port':53}])
        self.assertFalse(any(d['kind']=='Secret' for d in docs))

    def test_gameplay_host_rejects_path_or_wildcard(self):
        module = load('room_invalid_host', 'server/rooms/deploy.py')
        for host in ('bad/host', '*.example.com', 'example.com:80', 'localhost'):
            with self.assertRaises(ValueError): module.render('example/worker@sha256:'+'a'*64, True, host)

class PoolTests(unittest.TestCase):
    def test_pool_has_stable_independent_routes(self):
        docs, pool = load('room_pool', 'server/rooms/pool_deploy.py').render('example/worker@sha256:'+'a'*64)
        self.assertEqual(len(pool), 5)
        self.assertEqual(len(docs), 20)
        for index in range(5):
            deploy, service, policy, ingress = docs[index*4:index*4+4]
            name='room-worker-'+str(index)
            self.assertEqual(deploy['spec']['replicas'],1)
            self.assertEqual(service['spec']['selector'],{'app':name})
            self.assertEqual(policy['spec']['podSelector']['matchLabels'],{'app':name})
            route=ingress['spec']['rules'][0]['http']['paths'][0]
            self.assertEqual(route['pathType'],'Exact')
            self.assertEqual(route['path'],'/room/room-'+str(index))
            self.assertEqual(route['backend']['service']['name'],name)
            self.assertTrue(pool[index]['url'].endswith(route['path']))
    def test_pool_bounds(self):
        module=load('room_pool_bounds','server/rooms/pool_deploy.py')
        for count in [0,17]:
            with self.assertRaises(ValueError):module.render('example/worker@sha256:'+'a'*64,count)
