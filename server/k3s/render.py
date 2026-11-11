#!/usr/bin/env python3
"""Render reviewable Kubernetes JSON (also valid YAML); never contacts a cluster."""
import argparse
import json
import re

NAKAMA_IMAGE = 'registry.heroiclabs.com/heroiclabs/nakama:3.37.0@sha256:b475a1d7baf6f27be53abe30a59a29f10860ac3101780e626f90ff60107546a9'
POSTGRES_IMAGE = 'postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24'


def ref(secret, key):
    return {'secretKeyRef': {'name': secret, 'key': key}}


def env(name, secret, key):
    return {'name': name, 'valueFrom': ref(secret, key)}


def resources(cpu, memory, limit_cpu, limit_memory):
    return {'requests': {'cpu': cpu, 'memory': memory}, 'limits': {'cpu': limit_cpu, 'memory': limit_memory}}


def render(environment, host=None, ingress_class=None, tls_secret=None, backup_image=None):
    if environment not in ('staging', 'prod'):
        raise ValueError('environment must be staging or prod')
    if bool(host) != bool(ingress_class) or bool(host) != bool(tls_secret):
        raise ValueError('host, ingress class and TLS secret must be supplied together')
    if host and (not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?', host) or '.' not in host):
        raise ValueError('host must be a DNS hostname, without scheme/path')
    for value in (ingress_class, tls_secret):
        if value and not re.fullmatch(r'[a-z0-9][a-z0-9.-]*', value):
            raise ValueError('invalid Kubernetes name')
    if backup_image and not re.fullmatch(r'[^\s]+@sha256:[a-f0-9]{64}', backup_image):
        raise ValueError('backup image must be pinned by sha256 digest')
    namespace = 'zorx-' + environment
    items = [{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': namespace}}]

    def add(api, kind, name, **fields):
        items.append({'apiVersion': api, 'kind': kind, 'metadata': {'name': name, 'namespace': namespace}, **fields})

    def template(app, containers, **extras):
        return {'metadata': {'labels': {'app': app}}, 'spec': {
            'automountServiceAccountToken': False, 'containers': containers, **extras}}

    db_env = [{'name': 'POSTGRES_USER', 'value': 'postgres'}, {'name': 'POSTGRES_DB', 'value': 'postgres'},
              env('POSTGRES_PASSWORD', 'postgres-auth', 'admin-password'),
              {'name': 'PGDATA', 'value': '/var/lib/postgresql/data/pgdata'}]
    db = {'name': 'postgres', 'image': POSTGRES_IMAGE, 'env': db_env,
          'ports': [{'name': 'postgres', 'containerPort': 5432}],
          'resources': resources('250m', '256Mi', '2', '2Gi'),
          'securityContext': {'allowPrivilegeEscalation': False, 'capabilities': {'drop': ['ALL']}},
          'readinessProbe': {'exec': {'command': ['pg_isready', '-U', 'postgres', '-d', 'postgres']}, 'periodSeconds': 5},
          'startupProbe': {'exec': {'command': ['pg_isready', '-U', 'postgres', '-d', 'postgres']}, 'periodSeconds': 5, 'failureThreshold': 60},
          'volumeMounts': [{'name': 'data', 'mountPath': '/var/lib/postgresql/data'},
                           {'name': 'init', 'mountPath': '/docker-entrypoint-initdb.d', 'readOnly': True}]}
    add('v1', 'Service', 'postgres', spec={'clusterIP': 'None', 'selector': {'app': 'postgres'}, 'ports': [{'port': 5432, 'targetPort': 'postgres'}]})
    add('apps/v1', 'StatefulSet', 'postgres', spec={'serviceName': 'postgres', 'replicas': 1,
        'selector': {'matchLabels': {'app': 'postgres'}},
        'template': template('postgres', [db], securityContext={'runAsUser': 70, 'runAsGroup': 70, 'runAsNonRoot': True, 'fsGroup': 70},
            volumes=[{'name': 'init', 'secret': {'secretName': 'postgres-auth', 'defaultMode': 288,
                     'items': [{'key': 'init.sql', 'path': '01-nakama.sql'}]}}]),
        'volumeClaimTemplates': [{'metadata': {'name': 'data'}, 'spec': {'accessModes': ['ReadWriteOnce'], 'resources': {'requests': {'storage': '10Gi'}}}}]})
    security = {'runAsNonRoot': True, 'runAsUser': 10001, 'runAsGroup': 10001, 'fsGroup': 10001}
    restricted = {'allowPrivilegeEscalation': False, 'readOnlyRootFilesystem': True, 'capabilities': {'drop': ['ALL']}}
    mounts = [{'name': 'config', 'mountPath': '/run/nakama', 'readOnly': True}, {'name': 'data', 'mountPath': '/nakama/data'}, {'name': 'tmp', 'mountPath': '/tmp'}]
    health = {'exec': {'command': ['/nakama/nakama', 'healthcheck']}, 'periodSeconds': 10, 'timeoutSeconds': 5}
    nk = {'name': 'nakama', 'image': NAKAMA_IMAGE, 'command': ['/nakama/nakama'], 'args': ['--config', '/run/nakama/config.yml'],
          'ports': [{'name': 'api', 'containerPort': 7350}], 'securityContext': restricted,
          'volumeMounts': mounts, 'resources': resources('250m', '256Mi', '2', '1Gi'),
          'readinessProbe': health, 'livenessProbe': {**health, 'failureThreshold': 6},
          'startupProbe': {**health, 'failureThreshold': 60}}
    migrate = {'name': 'migrate', 'image': NAKAMA_IMAGE, 'command': ['/nakama/nakama'],
               'args': ['migrate', 'up', '--config', '/run/nakama/config.yml'], 'securityContext': restricted,
               'volumeMounts': mounts, 'resources': resources('100m', '128Mi', '1', '512Mi')}
    add('apps/v1', 'Deployment', 'nakama', spec={'replicas': 1, 'strategy': {'type': 'Recreate'},
        'selector': {'matchLabels': {'app': 'nakama'}}, 'template': template('nakama', [nk],
            securityContext=security, initContainers=[migrate], volumes=[
                {'name': 'config', 'secret': {'secretName': 'nakama-config', 'defaultMode': 288}},
                {'name': 'data', 'emptyDir': {}}, {'name': 'tmp', 'emptyDir': {}}])})
    add('v1', 'Service', 'nakama', spec={'selector': {'app': 'nakama'}, 'ports': [{'port': 7350, 'targetPort': 'api'}]})
    add('networking.k8s.io/v1', 'NetworkPolicy', 'postgres-isolated', spec={
        'podSelector': {'matchLabels': {'app': 'postgres'}}, 'policyTypes': ['Ingress'],
        'ingress': [{'from': [{'podSelector': {'matchLabels': {'app': app}}} for app in ('nakama', 'postgres-backup')],
                     'ports': [{'protocol': 'TCP', 'port': 5432}]}]})
    add('networking.k8s.io/v1', 'NetworkPolicy', 'nakama-api-only', spec={
        'podSelector': {'matchLabels': {'app': 'nakama'}}, 'policyTypes': ['Ingress'],
        'ingress': [{'ports': [{'protocol': 'TCP', 'port': 7350}]}]})
    if host:
        add('networking.k8s.io/v1', 'Ingress', 'nakama', spec={
            'ingressClassName': ingress_class, 'tls': [{'hosts': [host], 'secretName': tls_secret}],
            'rules': [{'host': host, 'http': {'paths': [{'path': '/', 'pathType': 'Prefix', 'backend': {'service': {'name': 'nakama', 'port': {'number': 7350}}}}]}}]})
    if backup_image:
        backup = {'name': 'backup', 'image': backup_image, 'args': ['backup'],
            'env': [{'name': 'PGHOST', 'value': 'postgres'}, {'name': 'PGDATABASE', 'value': 'nakama'},
                    {'name': 'PGUSER', 'value': 'nakama'}, env('PGPASSWORD', 'postgres-auth', 'app-password'),
                    {'name': 'BACKUP_PREFIX', 'value': namespace + '/'}],
            'envFrom': [{'secretRef': {'name': 'backup-s3'}}], 'securityContext': restricted,
            'volumeMounts': [{'name': 'tmp', 'mountPath': '/tmp'}], 'resources': resources('100m', '128Mi', '1', '512Mi')}
        add('batch/v1', 'CronJob', 'postgres-backup', spec={'schedule': '0 2 * * *', 'timeZone': 'Etc/UTC',
            'suspend': True, 'concurrencyPolicy': 'Forbid', 'successfulJobsHistoryLimit': 3, 'failedJobsHistoryLimit': 3,
            'jobTemplate': {'spec': {'backoffLimit': 2, 'activeDeadlineSeconds': 1800,
                'template': template('postgres-backup', [backup], restartPolicy='Never',
                    securityContext=security, volumes=[{'name': 'tmp', 'emptyDir': {}}])}}})
    return {'apiVersion': 'v1', 'kind': 'List', 'items': items}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', choices=['staging', 'prod'], required=True)
    parser.add_argument('--host')
    parser.add_argument('--ingress-class')
    parser.add_argument('--tls-secret')
    parser.add_argument('--backup-image')
    args = parser.parse_args()
    try:
        print(json.dumps(render(**vars(args)), indent=2))
    except ValueError as exc:
        parser.error(str(exc))


if __name__ == '__main__':
    main()
