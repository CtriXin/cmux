#!/usr/bin/env bash
# Audit that the local cmux branch still carries the CtriXin fix stack after an
# upstream sync.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REF="${1:-origin/main}"
cd "$REPO_ROOT"

failures=0

ok() {
  printf 'ok: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_marker() {
  local label="$1"
  local file="$2"
  local pattern="$3"

  if [[ ! -e "$file" ]]; then
    fail "$label missing file: $file"
    return
  fi

  if rg -q "$pattern" "$file"; then
    ok "$label"
  else
    fail "$label missing marker '$pattern' in $file"
  fi
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "command available: $1"
  else
    fail "command missing: $1"
  fi
}

require_command git
require_command rg
require_command python3

if git rev-parse --verify --quiet "${UPSTREAM_REF}^{commit}" >/dev/null; then
  ok "upstream ref exists: $UPSTREAM_REF ($(git rev-parse --short "$UPSTREAM_REF"))"
else
  fail "upstream ref not found: $UPSTREAM_REF; run 'git fetch origin +main:refs/remotes/origin/main'"
fi

if [[ $failures -eq 0 ]] && git merge-base --is-ancestor "$UPSTREAM_REF" HEAD; then
  ok "HEAD contains $UPSTREAM_REF"
elif [[ $failures -eq 0 ]]; then
  fail "HEAD does not contain $UPSTREAM_REF; replay local fixes on latest upstream before shipping"
fi

if [[ $failures -eq 0 ]]; then
  if git diff --check "$UPSTREAM_REF" -- >/dev/null; then
    ok "local delta has no whitespace errors"
  else
    git diff --check "$UPSTREAM_REF" -- || true
    fail "local delta has whitespace errors"
  fi
fi

if rg -n '^(<<<<<<<|=======|>>>>>>>)' Sources Packages cmux.xcodeproj/project.pbxproj cmuxTests CLI docs scripts >/tmp/cmux-sync-conflict-markers.$$ 2>/dev/null; then
  cat /tmp/cmux-sync-conflict-markers.$$
  rm -f /tmp/cmux-sync-conflict-markers.$$
  fail "conflict markers remain"
else
  rm -f /tmp/cmux-sync-conflict-markers.$$
  ok "no conflict markers in high-risk paths"
fi

if [[ -x scripts/check-pbxproj.sh ]]; then
  if scripts/check-pbxproj.sh >/dev/null; then
    ok "pbxproj normalization check"
  else
    scripts/check-pbxproj.sh || true
    fail "pbxproj normalization check"
  fi
fi

require_marker "session upstream error model flag" "Sources/SessionIndexModels.swift" "hasUpstreamError"
require_marker "session upstream error detector" "Sources/SessionIndexStore.swift" "hasUpstreamErrorSignal"
require_marker "session upstream error row stroke" "Sources/SessionIndexView.swift" "upstreamErrorRowStroke"
require_marker "Codex rollout path tail scan" "Sources/SessionIndexStore+CodexSQL.swift" "fileHasUpstreamErrorSignal"
require_marker "OpenCode completion notification path" "Sources/VaultAgentProcessScanner.swift" "processOpenCodeCompletionNotifications"
require_marker "OpenCode scoped process filter" "Sources/VaultAgentProcessScanner.swift" "scopedProcessIDsByPanelKey"
require_marker "OpenCode completion localization key" "Resources/Localizable.xcstrings" "opencode\\.completion\\.title"
require_marker "terminal raw copy menu" "Sources/GhosttyTerminalView.swift" "terminalContextMenu\\.copyRaw"
require_marker "terminal cleaned copy helper" "Sources/Terminal/TerminalCopyCleaner.swift" "TerminalCopyCleaner"
require_marker "browser external open affordance" "Sources/Panels/BrowserPanelView.swift" "browser\\.openInDefaultBrowser"
require_marker "terminal title spinner filter" "Sources/TabManager.swift" "stableTerminalPanelTitle"
require_marker "terminal title publish filter" "Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface+TitlePublishing.swift" "publishableTerminalTitle"
require_marker "notification unread phone sync" "Sources/TerminalController+MobileNotificationSync.swift" "notification\\.dismissed"
require_marker "DEV dmg packaging script" "scripts/package-dev-dmg.sh" "cmux-dev"

python3 - <<'PY'
import json
import sys
from pathlib import Path

path = Path("Resources/Localizable.xcstrings")
data = json.loads(path.read_text())
strings = data.get("strings", {})
required_keys = [
    "opencode.completion.title",
    "opencode.completion.subtitle",
    "opencode.completion.fallbackBody",
    "terminalContextMenu.copyRaw",
    "terminalContextMenu.copyCleaned",
]
required_locales = {"en", "ja"}
missing = []
for key in required_keys:
    entry = strings.get(key)
    if not entry:
        missing.append(f"{key}: missing key")
        continue
    locales = set(entry.get("localizations", {}))
    missing_locales = sorted(required_locales - locales)
    if missing_locales:
        missing.append(f"{key}: missing locales {', '.join(missing_locales)}")

if missing:
    for item in missing:
        print(f"FAIL: localization {item}", file=sys.stderr)
    sys.exit(1)

print("ok: required local localization keys include en/ja")
PY
if [[ $? -ne 0 ]]; then
  failures=$((failures + 1))
fi

echo
echo "Local delta summary against $UPSTREAM_REF:"
git diff --shortstat "$UPSTREAM_REF" -- || true
git diff --name-status "$UPSTREAM_REF" -- | sed -n '1,120p'

if [[ $failures -ne 0 ]]; then
  echo
  echo "Sync audit failed with $failures problem(s)." >&2
  exit 1
fi

echo
echo "Sync audit passed."
