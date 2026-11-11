import importlib.util
import json
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/backend'))
# Runner unit tests do not need a live cluster or the optional image-only dependency.
kube = types.ModuleType('kubernetes'); kube.client = MagicMock(); kube.config = MagicMock()
streams = types.ModuleType('kubernetes.stream'); streams.stream = MagicMock()
with patch.dict(sys.modules, {'kubernetes': kube, 'kubernetes.stream': streams}):
    spec = importlib.util.spec_from_file_location('maintenance', ROOT / 'tools/backend/registry_maintenance.py')
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


REAL_PATCH_MODE = m.patch_mode
REAL_READONLY = m.readonly

class Maintenance(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        policy = Path(self.tmp.name) / 'policy.json'
        policy.write_text(json.dumps(dict(apply_enabled=True, keep_latest=10, minimum_age_days=14,
                                         repositories=['zorx-web'])))
        self.patches = [patch.object(m, 'POLICY', policy), patch.object(m, 'collect_refs', return_value={'live'}),
                        patch.object(m, 'readonly', return_value=False), patch.object(m, 'Registry'),
                        patch.object(m, 'plan', return_value=[]), patch.object(m, 'ready', return_value='registry-pod'),
                        patch.object(m, 'execute'), patch.object(m, 'patch_mode'), patch.object(m, 'terminate_gc')]
        self.mocks = [p.start() for p in self.patches]
        for p in self.patches: self.addCleanup(p.stop)
        kube.client.reset_mock(); kube.config.reset_mock()
        self.dep = kube.client.AppsV1Api.return_value.read_namespaced_deployment.return_value
        self.dep.metadata.annotations = {}; self.dep.metadata.resource_version = '10'
        self.registry = m.Registry.return_value
        self.registry.records.return_value = []

    def test_empty_plan_does_not_interrupt_push(self):
        m.run(); m.patch_mode.assert_not_called(); m.execute.assert_not_called()

    def test_lock_before_delete_and_freeze_before_gc(self):
        m.plan.return_value = [dict(repository='zorx-web', digest='sha256:a', reason='expired')]
        m.run()
        patch_call = kube.client.AppsV1Api.return_value.patch_namespaced_deployment.call_args
        self.assertEqual(patch_call.args[2][0]['op'], 'test')
        self.registry.request.assert_called_once_with('/v2/zorx-web/manifests/sha256:a', 'DELETE')
        self.assertTrue(m.patch_mode.call_args_list[0].args[1])
        self.assertFalse(m.patch_mode.call_args_list[-1].args[1])
        self.assertNotIn('--delete-untagged', ' '.join(m.execute.call_args.args[2]))
        m.terminate_gc.assert_not_called()

    def test_failed_gc_terminates_process_before_restore(self):
        events = []
        m.execute.side_effect = RuntimeError('lost connection')
        m.terminate_gc.side_effect = lambda *_: events.append('kill')
        m.patch_mode.side_effect = lambda _, enabled, *a: events.append(enabled)
        with self.assertRaises(RuntimeError): m.run(force_gc=True)
        self.assertEqual(events, [True, 'kill', False])

    def test_cannot_restore_writes_if_process_not_confirmed_dead(self):
        m.execute.side_effect = RuntimeError('lost connection')
        m.terminate_gc.side_effect = RuntimeError('pod still terminating')
        with self.assertRaises(RuntimeError): m.run(force_gc=True)
        self.assertTrue(all(c.args[1] for c in m.patch_mode.call_args_list))

    def test_workload_change_aborts_before_mutation(self):
        m.collect_refs.side_effect = [{'a'}, {'b'}]
        with self.assertRaises(RuntimeError): m.run(force_gc=True)
        m.patch_mode.assert_not_called(); self.registry.request.assert_not_called()

    def test_watchdog_waits_until_deadline_then_recovers(self):
        self.dep.metadata.annotations = {m.ANNOTATION: str(time.time() + 60)}
        m.run(watchdog=True); m.terminate_gc.assert_not_called()
        self.dep.metadata.annotations = {m.ANNOTATION: str(time.time() - 60)}
        m.run(watchdog=True); m.terminate_gc.assert_called_once()
        m.patch_mode.assert_called_once_with(kube.client.AppsV1Api.return_value, False)

    def test_existing_lock_blocks_overlap(self):
        self.dep.metadata.annotations = {m.ANNOTATION: str(time.time() + 60)}
        with self.assertRaises(RuntimeError): m.run(force_gc=True)
        self.registry.request.assert_not_called()

    def test_foreign_repository_is_rejected(self):
        p = m.POLICY; data = json.loads(p.read_text()); data['repositories'].append('other-project')
        p.write_text(json.dumps(data))
        with self.assertRaises(ValueError): m.run()
        self.registry.records.assert_not_called()


class ConfigSwitch(unittest.TestCase):
    def test_config_switch_uses_json_patch_and_preserves_storage(self):
        ns = types.SimpleNamespace
        container = ns(name='registry', args=['/etc/docker/registry/config.yml'])
        dep = ns(metadata=ns(annotations={'other': 'keep'}, resource_version='11'),
                 spec=ns(template=ns(spec=ns(containers=[container]))))
        apps = MagicMock(); apps.read_namespaced_deployment.return_value = dep
        REAL_PATCH_MODE(apps, True, '123')
        body = apps.patch_namespaced_deployment.call_args.args[2]
        self.assertEqual(body[0], dict(op='test', path='/metadata/resourceVersion', value='11'))
        self.assertEqual(body[1]['value'], {'other': 'keep', m.ANNOTATION: '123'})
        self.assertEqual(body[2]['value'], ['/etc/docker/registry/config-readonly.yml'])
        self.assertFalse(REAL_READONLY(dep))
        container.args = body[2]['value']
        self.assertTrue(REAL_READONLY(dep))
        self.assertTrue(REAL_READONLY(ns(spec=ns(containers=[container]))))
