#!/usr/bin/env python3
"""Line-oriented fake MCP guest for the mirror-vm check."""
import json
import os
import sys

with open(os.environ['FAKE_SCENARIO']) as f:
    scenario = json.load(f)

defaults = {
    'status': {'owner': 'agent', 'generation': 7},
    'control': {'ok': True},
    'screenshot': {'frame': 'f1', 'generation': 7},
}

for line in sys.stdin:
    request = json.loads(line)
    if request['method'] == 'initialize':
        result = {}
    else:
        call = request['params']
        name = call['name']
        with open(os.environ['FAKE_LOG'], 'a') as log:
            log.write(json.dumps({'name': name, 'arguments': call['arguments']}) + '\n')
        choices = scenario.get(name, [])
        body = choices.pop(0) if choices else defaults.get(name, {})
        result = {'content': [{'type': 'text', 'text': json.dumps(body)}], 'isError': False}
    sys.stdout.write(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}) + '\n')
    sys.stdout.flush()
