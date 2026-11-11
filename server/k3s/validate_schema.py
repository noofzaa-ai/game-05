#!/usr/bin/env python3
"""Optional offline OpenAPI validation. Supply an official Kubernetes swagger.json; no network/API calls."""
import argparse
import json
from pathlib import Path


def normalize(node):
    # Kubernetes' Swagger2 encodes IntOrString as type:string + custom format.
    # JSON Schema needs the actual accepted union; numeric service/policy ports are valid.
    if isinstance(node, dict):
        if node.get('format') == 'int-or-string':
            node['type'] = ['integer', 'string']
        for value in node.values(): normalize(value)
    elif isinstance(node, list):
        for value in node: normalize(value)


def main():
    import jsonschema
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--schema', type=Path, required=True)
    parser.add_argument('manifests', type=Path, nargs='+')
    args = parser.parse_args()
    schema = json.loads(args.schema.read_text())
    normalize(schema)
    count = 0
    for path in args.manifests:
        payload = json.loads(path.read_text())
        for obj in payload.get('items', [payload]):
            version = obj['apiVersion']
            group, version = version.split('/') if '/' in version else ('', version)
            matches = [key for key, value in schema['definitions'].items() if
                       {'group': group, 'version': version, 'kind': obj['kind']} in value.get('x-kubernetes-group-version-kind', [])]
            if len(matches) != 1: raise ValueError('Unknown or ambiguous resource: '+obj['kind'])
            jsonschema.Draft4Validator({'$ref': '#/definitions/'+matches[0], 'definitions': schema['definitions']}).validate(obj)
            count += 1
    print('PASS offline Kubernetes OpenAPI schema:', count, 'resources')


if __name__ == '__main__': main()
