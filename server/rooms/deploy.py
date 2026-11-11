#!/usr/bin/env python3
"""Render private one-CPU room worker resources using Boss's immutable image ref."""
import argparse
import os
from pathlib import Path
import re
import json
import yaml

NAMESPACE = 'zorx-staging'

def render(image, networking=False, host="zorxapi.daiyooo.com"):
    if not re.fullmatch(r'[^\s@]+@sha256:[a-f0-9]{64}', image): raise ValueError('Room image requires an immutable digest')
    def metadata(name): return {'name': name, 'namespace': NAMESPACE}
    security = {'runAsNonRoot': True, 'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True,
                'capabilities': {'drop': ['ALL']}, 'seccompProfile': {'type': 'RuntimeDefault'}}
    probe = {'httpGet': {'path': '/healthz', 'port': 'control'}, 'periodSeconds': 5, 'timeoutSeconds': 2}
    deployment = {'apiVersion': 'apps/v1', 'kind': 'Deployment', 'metadata': metadata('room-worker'), 'spec': {
        'replicas': 1, 'strategy': {'type': 'Recreate'}, 'selector': {'matchLabels': {'app': 'room-worker'}},
        'template': {'metadata': {'labels': {'app': 'room-worker'}}, 'spec': {
            'automountServiceAccountToken': False,
            'securityContext': {'runAsUser': 10001, 'runAsGroup': 10001, 'runAsNonRoot': True, 'fsGroup': 10001},
            'containers': [{'name': 'rooms', 'image': image, 'imagePullPolicy': 'IfNotPresent', 'securityContext': security,
                'env': [{'name': 'ZORX_WORKER_TOKEN', 'valueFrom': {'secretKeyRef': {'name': 'zorx-names-runtime', 'key': 'token'}}}],
                'ports': [{'name': 'control', 'containerPort': 8051}],
                'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}],
                'resources': {'requests': {'cpu': '1', 'memory': '256Mi'}, 'limits': {'cpu': '1', 'memory': '512Mi'}},
                'readinessProbe': probe, 'livenessProbe': dict(probe, failureThreshold=6),
                'startupProbe': dict(probe, failureThreshold=30)}],
            'volumes': [{'name': 'tmp', 'emptyDir': {}}]}}}}
    service = {'apiVersion': 'v1', 'kind': 'Service', 'metadata': metadata('room-worker'), 'spec': {
        'type': 'ClusterIP', 'selector': {'app': 'room-worker'}, 'ports': [{'port': 8051, 'targetPort': 'control'}]}}
    policy = {'apiVersion': 'networking.k8s.io/v1', 'kind': 'NetworkPolicy', 'metadata': metadata('room-worker-private'), 'spec': {
        'podSelector': {'matchLabels': {'app': 'room-worker'}}, 'policyTypes': ['Ingress', 'Egress'], 'egress': [],
        'ingress': [{'from': [{'podSelector': {'matchLabels': {'app': 'nakama'}}}], 'ports': [{'protocol': 'TCP', 'port': 8051}]}]}}
    result = [deployment, service, policy]
    if networking:
        if not re.fullmatch(r'[a-z0-9][a-z0-9.-]*[a-z0-9]', host) or '.' not in host: raise ValueError('Invalid public room host')
        container = deployment['spec']['template']['spec']['containers'][0]
        container['env'] += [{'name': 'ZORX_ROOM_NAKAMA_URL', 'value': 'http://nakama:7350'},
                            {'name': 'ZORX_ROOM_HTTP_KEY', 'valueFrom': {'secretKeyRef': {'name': 'zorx-room-server', 'key': 'http_key'}}}]
        container['ports'].append({'name': 'gameplay', 'containerPort': 8060})
        service['spec']['ports'].append({'name': 'gameplay', 'port': 8060, 'targetPort': 'gameplay'})
        service['spec']['ports'][0]['name'] = 'control'
        policy['spec']['egress'] = [
            {'to': [{'podSelector': {'matchLabels': {'app': 'nakama'}}}], 'ports': [{'protocol': 'TCP', 'port': 7350}]},
            {'to': [{'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'kube-system'}}, 'podSelector': {'matchLabels': {'k8s-app': 'kube-dns'}}}], 'ports': [{'protocol': 'UDP', 'port': 53}, {'protocol': 'TCP', 'port': 53}]}]
        policy['spec']['ingress'].append({'from': [{'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'kube-system'}}, 'podSelector': {'matchLabels': {'app.kubernetes.io/name': 'traefik'}}}], 'ports': [{'protocol': 'TCP', 'port': 8060}]})
        result.append({'apiVersion': 'networking.k8s.io/v1', 'kind': 'Ingress', 'metadata': {'name': 'room-gameplay', 'namespace': NAMESPACE, 'annotations': {'traefik.ingress.kubernetes.io/router.entrypoints': 'web', 'traefik.ingress.kubernetes.io/router.middlewares': 'zorx-staging-room-admission-budget@kubernetescrd'}},
                       'spec': {'ingressClassName': 'traefik', 'rules': [{'host': host, 'http': {'paths': [{'path': '/room', 'pathType': 'Prefix', 'backend': {'service': {'name': 'room-worker', 'port': {'number': 8060}}}}]}}]}})
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--networking', action='store_true')
    parser.add_argument('--host', default='zorxapi.daiyooo.com')
    parser.add_argument('--secrets', type=Path, help='Private original Nakama deployment bundle; extract runtime HTTP key only')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    documents = render(args.image, args.networking, args.host)
    if args.networking:
        if args.secrets is None: parser.error('--networking requires --secrets (private original bundle)')
        original = list(yaml.safe_load_all(args.secrets.read_text()))
        config = next(row['stringData']['config.yml'] for row in original if row and row.get('kind') == 'Secret' and row.get('metadata', {}).get('name') == 'nakama-config')
        key = json.loads(config)['runtime']['http_key']
        if not isinstance(key, str) or len(key) < 16: raise ValueError('Missing runtime HTTP key')
        documents.insert(0, {'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': 'zorx-room-server', 'namespace': NAMESPACE}, 'type': 'Opaque', 'stringData': {'http_key': key}})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600 if args.networking else 0o644)
    with os.fdopen(fd, 'w') as stream: yaml.safe_dump_all(documents, stream, sort_keys=False)
    print('Created private staging room resources; no remote apply')

if __name__ == '__main__': main()
