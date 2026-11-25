#!/usr/bin/env bash
# يشغّل اختبار منطق السماع offscreen بحالة معزولة (بلا نافذة ولا سرقة تركيز)
set -u
here="$(cd "$(dirname "$0")" && pwd)"; root="$here/../.."
tmp="$(mktemp -d "${TMPDIR:-/tmp}/qmltest.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
cp "$here/tst_listen_engine.qml" "$root/TasmeeEngine.qml" "$tmp/"
out="$(XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 qs -p "$tmp/tst_listen_engine.qml" 2>&1)"
echo "$out" | grep -E "PASS|FAIL|ERROR|qml:"
echo "$out" | grep -q "ALL PASS"
