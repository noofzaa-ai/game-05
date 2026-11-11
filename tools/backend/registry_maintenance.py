#!/usr/bin/env python3
"""Shared registry retention runner. Requires in-cluster service account, never admin kubeconfig."""
import datetime as dt
import json
import os
import sys
import time
from pathlib import Path

from kubernetes import client, config
from kubernetes.stream import stream
from image_retention import Registry, plan, workload_refs

NS = 'registry'
DEPLOYMENT = 'docker-registry'
ANNOTATION = 'zorx.io/maintenance-deadline'
READONLY = 'REGISTRY_STORAGE_MAINTENANCE_READONLY_ENABLED'
POLICY = Path('/policy/image_retention_policy.json')


def collect_refs(core, apps, batch):
    # Include completed workloads and ReplicaSets: their images may be used for rollback.
    objects = [core.list_pod_for_all_namespaces(), apps.list_deployment_for_all_namespaces(),
               apps.list_stateful_set_for_all_namespaces(), apps.list_daemon_set_for_all_namespaces(),
               apps.list_replica_set_for_all_namespaces(), batch.list_job_for_all_namespaces(),
               batch.list_cron_job_for_all_namespaces()]
    return workload_refs(client.ApiClient().sanitize_for_serialization(objects))


def pods(core):
    return core.list_namespaced_pod(NS, label_selector='app=docker-registry').items


def readonly(deployment):
    spec = deployment.spec.template.spec if hasattr(deployment.spec, 'template') else deployment.spec
    return any('/etc/docker/registry/config-readonly.yml' in (c.args or [])
               for c in spec.containers if c.name == 'registry')


def patch_mode(apps, enabled, deadline=None):
    dep = apps.read_namespaced_deployment(DEPLOYMENT, NS)
    annotations = dict(dep.metadata.annotations or {})
    if deadline is None: annotations.pop(ANNOTATION, None)
    else: annotations[ANNOTATION] = deadline
    index, container = next((i, c) for i, c in enumerate(dep.spec.template.spec.containers)
                            if c.name == 'registry')
    target = '/etc/docker/registry/config-readonly.yml' if enabled else '/etc/docker/registry/config.yml'
    apps.patch_namespaced_deployment(DEPLOYMENT, NS, [
        {'op': 'test', 'path': '/metadata/resourceVersion', 'value': dep.metadata.resource_version},
        {'op': 'add', 'path': '/metadata/annotations', 'value': annotations},
        {'op': 'add', 'path': f'/spec/template/spec/containers/{index}/args', 'value': [target]}])


def ready(core, apps, enabled, timeout=180):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        dep = apps.read_namespaced_deployment(DEPLOYMENT, NS)
        current = pods(core)
        # No old/terminating writable pods may survive before GC starts.
        if (len(current) == 1 and not current[0].metadata.deletion_timestamp
                and readonly(dep) == enabled
                and readonly(current[0]) == enabled
                and dep.status.observed_generation == dep.metadata.generation
                and dep.status.updated_replicas == 1 and dep.status.available_replicas == 1):
            return current[0].metadata.name
        time.sleep(2)
    raise RuntimeError('Registry rollout did not converge')


def execute(core, pod, command):
    ws = stream(client.CoreV1Api(client.ApiClient()).connect_get_namespaced_pod_exec, pod, NS, container='registry',
                command=command, stderr=True, stdin=False, stdout=True, tty=False,
                _preload_content=False)
    until = time.monotonic() + 660
    try:
        while ws.is_open() and time.monotonic() < until:
            ws.update(timeout=2)
            if ws.peek_stdout(): print(ws.read_stdout(), end='', flush=True)
            if ws.peek_stderr(): print(ws.read_stderr(), end='', file=sys.stderr, flush=True)
        if ws.is_open(): raise TimeoutError('GC exec did not finish')
        if ws.returncode != 0: raise RuntimeError('Registry command failed: ' + str(ws.returncode))
    finally:
        ws.close()


def terminate_gc(core):
    # A lost exec connection is not proof that GC stopped. Terminate its pod before writes resume.
    old = [(p.metadata.name, p.metadata.uid) for p in pods(core)]
    for name, _ in old:
        core.delete_namespaced_pod(name, NS, grace_period_seconds=30)
    until = time.monotonic() + 180
    while time.monotonic() < until:
        if not {p.metadata.uid for p in pods(core)} & {uid for _, uid in old}: return
        time.sleep(2)
    raise RuntimeError('Old registry pod still exists; writes remain frozen')


def run(watchdog=False, force_gc=False):
    config.load_incluster_config()
    core, apps, batch = client.CoreV1Api(), client.AppsV1Api(), client.BatchV1Api()
    dep = apps.read_namespaced_deployment(DEPLOYMENT, NS)
    deadline = (dep.metadata.annotations or {}).get(ANNOTATION)
    if watchdog:
        if deadline and time.time() > float(deadline):
            print('Expired maintenance: terminating possible GC before restoring writes', flush=True)
            terminate_gc(core)
            patch_mode(apps, False)
            ready(core, apps, False)
            print('RECOVERED registry writes', flush=True)
        return
    if deadline or readonly(dep): raise RuntimeError('Registry already in maintenance; refusing overlap')
    policy = json.loads(POLICY.read_text())
    if not policy.get('apply_enabled'): raise RuntimeError('Retention apply disabled')
    if policy['keep_latest'] < 3 or policy['minimum_age_days'] < 7: raise ValueError('Unsafe policy')
    allowed = {'zorx-web', 'zorx-landing', 'zorx-nakama', 'zorx-name-validator', 'zorx-room-worker'}
    if not set(policy['repositories']) <= allowed: raise ValueError('Repository outside Zorx allowlist')
    refs = collect_refs(core, apps, batch)
    registry = Registry('http://docker-registry.registry.svc.cluster.local:5000')
    records = registry.records(policy['repositories'])
    result = plan(records, refs, policy, time.time())
    candidates = sorted({(r['repository'], r['digest']) for r in result if r['reason'] == 'expired'})
    print(json.dumps({'at': dt.datetime.now(dt.timezone.utc).isoformat(),
                      'scanned_tags': len(records), 'candidates': candidates, 'images': result}), flush=True)
    if not candidates and not force_gc:
        print('No expired manifests; no write interruption or GC needed', flush=True)
        return
    if collect_refs(core, apps, batch) != refs: raise RuntimeError('Workloads changed; aborting')
    # CAS lock prevents concurrent manual/CronJob runs; watchdog owns expired locks.
    dep = apps.read_namespaced_deployment(DEPLOYMENT, NS)
    if (dep.metadata.annotations or {}).get(ANNOTATION) or readonly(dep):
        raise RuntimeError('Maintenance lock appeared')
    deadline = str(time.time() + 1200)
    annotations = dict(dep.metadata.annotations or {})
    annotations[ANNOTATION] = deadline
    apps.patch_namespaced_deployment(DEPLOYMENT, NS, [
        {'op': 'test', 'path': '/metadata/resourceVersion', 'value': dep.metadata.resource_version},
        {'op': 'add', 'path': '/metadata/annotations', 'value': annotations}])
    completed = False
    try:
        if collect_refs(core, apps, batch) != refs: raise RuntimeError('Workloads changed; aborting')
        for repo, digest in candidates:
            registry.request('/v2/' + repo + '/manifests/' + digest, 'DELETE')
        patch_mode(apps, True, deadline)
        pod = ready(core, apps, True)
        execute(core, pod, ['sh', '-c', 'du -sk /var/lib/registry; timeout 600 /bin/registry garbage-collect /etc/docker/registry/config.yml; result=$?; du -sk /var/lib/registry; exit "$result"'])
        completed = True
    finally:
        if not completed: terminate_gc(core)
        patch_mode(apps, False)
        ready(core, apps, False)
        print('Registry writable again', flush=True)


if __name__ == '__main__':
    run(watchdog='--watchdog' in sys.argv, force_gc='--force-gc' in sys.argv)
