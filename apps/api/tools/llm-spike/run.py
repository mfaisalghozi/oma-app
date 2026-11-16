#!/usr/bin/env python3
"""Offline preparation or explicit, synthetic-only Bedrock benchmark."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).parent
MODEL = 'anthropic.claude-haiku-4-5'
ENDPOINT = 'https://bedrock-mantle.ap-northeast-1.api.aws/anthropic/v1/messages'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--live', action='store_true')
    mode.add_argument('--fixture', type=Path)
    parser.add_argument('--approval', type=Path, help='Operator attestation JSON, required for live')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    dataset_bytes = (ROOT / 'queries.json').read_bytes()
    dataset = json.loads(dataset_bytes)
    if len(dataset) != 50 or len({x['id'] for x in dataset}) != 50:
        parser.error('dataset must contain exactly 50 unique cases')
    token = os.environ.get('AWS_BEARER_TOKEN_BEDROCK')
    if args.live:
        if not token:
            parser.error('AWS_BEARER_TOKEN_BEDROCK is absent; no provider calls made')
        approval = json.loads(args.approval.read_text()) if args.approval else {}
        expected = {'model': MODEL, 'region': 'ap-northeast-1', 'routing': 'in-region',
                    'data_retention_mode': 'none', 'content_logging_disabled': True}
        if any(approval.get(k) != v for k, v in expected.items()) or not approval.get('evidence'):
            parser.error('operator attestation must verify model, Tokyo in-region routing, ZDR, logging and evidence')
    schema = json.loads((ROOT / 'schema.json').read_text())
    prompt = (ROOT / 'prompt.txt').read_text()
    report = {'live': bool(args.live), 'mode': 'live' if args.live else 'fixture' if args.fixture else 'prepared',
              'model': MODEL, 'region': 'ap-northeast-1', 'dataset_sha256': hashlib.sha256(dataset_bytes).hexdigest(),
              'prompt_sha256': hashlib.sha256(prompt.encode()).hexdigest(),
              'schema_sha256': hashlib.sha256(json.dumps(schema, sort_keys=True).encode()).hexdigest(),
              'p90_ms': None, 'cost_per_search_usd': None, 'queries': []}
    if args.live:
        report['approval'] = approval
    opener = urllib.request.build_opener(NoRedirect)
    for case in dataset:
        row = {'id': case['id'], 'status': 'prepared'}
        if not args.prepare:
            started = time.monotonic()
            try:
                if args.fixture:
                    response = json.loads(args.fixture.read_text())
                else:
                    body = {'model': MODEL, 'max_tokens': 1500, 'temperature': 0,
                            'system': prompt, 'messages': [{'role': 'user', 'content': case['query']}],
                            'output_config': {'format': {'type': 'json_schema', 'schema': schema}}}
                    req = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode(), headers={
                        'Content-Type': 'application/json', 'x-api-key': token, 'anthropic-version': '2023-06-01'})
                    with opener.open(req, timeout=10) as result:
                        raw = result.read(128 * 1024 + 1)
                        if len(raw) > 128 * 1024:
                            raise ValueError('oversized response')
                        response = json.loads(raw)
                row['elapsed_ms'] = round((time.monotonic() - started) * 1000, 3)
                row['usage'] = response['usage']
                # Retain provider text for independent schema and semantic review; JSON alone is not accuracy.
                row['output'] = json.loads(''.join(x['text'] for x in response['content'] if x['type'] == 'text'))
                row['stop_reason'] = response.get('stop_reason')
                row['status'] = 'received' if response.get('stop_reason') == 'end_turn' else 'incomplete'
            except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError, TypeError) as error:
                # Provider error bodies can contain request content; save only the class and HTTP status.
                row['status'] = 'failed'
                row['error_class'] = type(error).__name__
                row['http_status'] = getattr(error, 'code', None)
        report['queries'].append(row)
        if args.live:
            print(case['id'], row['status'], flush=True)
        # Preserve paid successes even when a later request fails or the process is interrupted.
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    received = [r for r in report['queries'] if r['status'] == 'received']
    report['received_count'] = len(received)
    if args.live and len(received) == 50:
        report['p90_ms'] = sorted(r['elapsed_ms'] for r in received)[math.ceil(0.9 * 50) - 1]
        # Standard Tokyo in-region rates, no cache/batch; estimates exclude tax and network charges.
        report['cost_per_search_usd'] = sum(
            (r['usage']['input_tokens'] * 1.10 + r['usage']['output_tokens'] * 5.50) / 1_000_000
            for r in received) / 50
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if args.live and len(received) != 50:
        raise SystemExit('Incomplete live benchmark; cost/search and p90 withheld')


if __name__ == '__main__':
    main()
