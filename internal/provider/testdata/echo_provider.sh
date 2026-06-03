#!/usr/bin/env bash
# Minimal fake provider: emits hello + devices + one state, then idles.
echo '{"type":"hello","protocol":1,"provider":{"id":"fake","name":"Fake","version":"0.0.1"}}'
echo '{"type":"devices","devices":[{"id":"d1","name":"D1","entities":[{"key":"battery","kind":"sensor","unit":"%"}]}]}'
echo '{"type":"state","device":"d1","values":{"battery":42}}'
# Stay alive so the host can observe a running process; exit on stdin close.
cat >/dev/null
