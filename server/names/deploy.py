#!/usr/bin/env python3
"""Render an apply-only staging name-service overlay; preserves original DB/API Secrets."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server/k3s'))
from standalone import resources as base_resources

SECRET = 'zorx-names-runtime'
NAMESPACE = 'zorx-staging'


def pinned(image):
    return bool(re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}', image))


def render(worker_image, nakama_image, token, room_ws_url="", room_workers=None, beta_test_kit=False):
    if not pinned(worker_image) or not pinned(nakama_image):
        raise ValueError('Both server images must use registry @sha256 digests')
    if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', token):
        raise ValueError('Invalid private validator token')
    runtime = {'runtime': {'path': '/opt/zorx/modules', 'js_entrypoint': 'index.js',
                          'env': ['ZORX_NAMES_URL=http://name-validator:8051', 'ZORX_NAMES_TOKEN=' + token, 'ZORX_RPC_BURST=20', 'ZORX_RPC_REFILL=5', 'ZORX_RPC_AUDIT_THRESHOLD=8', 'ZORX_REQUIRE_GOOGLE=1']}}
    if beta_test_kit:
        raise ValueError("Full catalog grants are retired; omit --beta-test-kit")
    if room_ws_url:
        if not re.fullmatch(r'wss://[a-z0-9.-]+(?::[0-9]+)?/room', room_ws_url): raise ValueError('Public room URL must be wss://HOST/room')
        runtime['runtime']['env'].append('ZORX_ROOM_WS_URL=' + room_ws_url)
    if room_workers:
        if not room_ws_url: raise ValueError("Pool requires base room URL")
        if not isinstance(room_workers, list) or not 1 <= len(room_workers) <= 16: raise ValueError("Invalid worker pool")
        for worker in room_workers:
            if set(worker) != {"id", "url"} or not re.fullmatch(r"[a-z0-9-]{1,40}", worker["id"]) or not re.fullmatch(r"wss://[a-z0-9.-]+/room/[a-z0-9-]+", worker["url"]): raise ValueError("Invalid worker route")
        if len({worker["id"] for worker in room_workers}) != len(room_workers): raise ValueError("Duplicate worker")
        runtime["runtime"]["env"].append("ZORX_ROOM_WORKERS=" + json.dumps(room_workers, separators=(",", ":")))
    runtime_text = json.dumps(runtime)
    checksum = hashlib.sha256(runtime_text.encode()).hexdigest()
    def meta(name): return {'name': name, 'namespace': NAMESPACE}
    restricted = {'runAsNonRoot': True, 'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True,
                  'capabilities': {'drop': ['ALL']}, 'seccompProfile': {'type': 'RuntimeDefault'}}
    secret = {'apiVersion': 'v1', 'kind': 'Secret', 'metadata': meta(SECRET), 'type': 'Opaque',
              'stringData': {'token': token, 'runtime.yml': runtime_text}}
    probe = {'httpGet': {'path': '/healthz', 'port': 'http'}, 'periodSeconds': 5, 'timeoutSeconds': 2}
    worker = {'apiVersion': 'apps/v1', 'kind': 'Deployment', 'metadata': meta('name-validator'), 'spec': {
        'replicas': 1, 'strategy': {'type': 'Recreate'}, 'selector': {'matchLabels': {'app': 'name-validator'}},
        'template': {'metadata': {'labels': {'app': 'name-validator'}, 'annotations': {'zorx/names-config-sha256': checksum}},
                     'spec': {'automountServiceAccountToken': False,
                              'securityContext': {'runAsUser': 10001, 'runAsGroup': 10001, 'runAsNonRoot': True, 'fsGroup': 10001},
                              'containers': [{'name': 'validator', 'image': worker_image, 'imagePullPolicy': 'IfNotPresent',
                                  'securityContext': restricted, 'ports': [{'name': 'http', 'containerPort': 8051}],
                                  'env': [{'name': 'ZORX_NAMES_TOKEN', 'valueFrom': {'secretKeyRef': {'name': SECRET, 'key': 'token'}}}],
                                  'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}],
                                  'resources': {'requests': {'cpu': '100m', 'memory': '128Mi'}, 'limits': {'cpu': '1', 'memory': '384Mi'}},
                                  'readinessProbe': probe, 'livenessProbe': {**probe, 'failureThreshold': 6},
                                  'startupProbe': {**probe, 'failureThreshold': 60}}],
                              'volumes': [{'name': 'tmp', 'emptyDir': {}}]}}}}
    service = {'apiVersion': 'v1', 'kind': 'Service', 'metadata': meta('name-validator'),
               'spec': {'type': 'ClusterIP', 'selector': {'app': 'name-validator'}, 'ports': [{'port': 8051, 'targetPort': 'http'}]}}
    policy = {'apiVersion': 'networking.k8s.io/v1', 'kind': 'NetworkPolicy', 'metadata': meta('name-validator-private'), 'spec': {
        'podSelector': {'matchLabels': {'app': 'name-validator'}}, 'policyTypes': ['Ingress', 'Egress'], 'egress': [],
        'ingress': [{'from': [{'podSelector': {'matchLabels': {'app': 'nakama'}}}], 'ports': [{'protocol': 'TCP', 'port': 8051}]}]}}
    nakama = copy.deepcopy(next(d for d in base_resources() if d['kind'] == 'Deployment' and d['metadata']['name'] == 'nakama'))
    pod = nakama['spec']['template']
    pod['metadata'].setdefault('annotations', {})['zorx/names-config-sha256'] = checksum
    container = pod['spec']['containers'][0]
    container['image'] = nakama_image
    container['args'] += ['--config', '/run/zorx-names/runtime.yml']
    container['volumeMounts'].append({'name': 'names-runtime', 'mountPath': '/run/zorx-names', 'readOnly': True})
    pod['spec']['volumes'].append({'name': 'names-runtime', 'secret': {'secretName': SECRET, 'defaultMode': 288,
                                                                   'items': [{'key': 'runtime.yml', 'path': 'runtime.yml'}]}})
    return [secret, worker, service, policy, nakama]


def token_from(path):
    secret = next(d for d in yaml.safe_load_all(path.read_text()) if d and d.get('kind') == 'Secret' and d.get('metadata', {}).get('name') == SECRET)
    return secret['stringData']['token']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--beta-test-kit', action='store_true', help='Retired: rejected; accounts now keep starter/equipped gear only')
    parser.add_argument('--worker-image', required=True)
    parser.add_argument('--nakama-image', required=True)
    parser.add_argument('--room-ws-url', default='', help='Public wss://HOST/room; optional until room rollout')
    parser.add_argument('--room-workers-file', type=Path, help='JSON worker pool generated from pool_deploy.py runtime env')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reuse-secret', type=Path, help='Previous private names bundle; reuse its token on updates')
    parser.add_argument('--resources-only', action='store_true', help='Review resources with Secret references only; requires --reuse-secret')
    args = parser.parse_args()
    if args.resources_only and not args.reuse_secret:
        parser.error('--resources-only requires --reuse-secret to retain rollout checksum')
    token = token_from(args.reuse_secret) if args.reuse_secret else secrets.token_urlsafe(32)
    documents = render(args.worker_image, args.nakama_image, token, args.room_ws_url, json.loads(args.room_workers_file.read_text()) if args.room_workers_file else None, args.beta_test_kit)
    if args.resources_only: documents = documents[1:]
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644 if args.resources_only else 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write('# Generated by server/names/deploy.py. ' + ('Resources only.\n' if args.resources_only else 'PRIVATE: new validator Secret; keep out of Git.\n'))
        yaml.safe_dump_all(documents, stream, sort_keys=False, allow_unicode=True)
    print('Created staging names overlay; original DB/API/signing Secrets are unchanged. No remote apply.')


if __name__ == '__main__':
    main()
