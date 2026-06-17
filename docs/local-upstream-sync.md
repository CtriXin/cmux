# Local upstream sync checklist

Use this when upstream `manaflow-ai/cmux` moves and the local CtriXin branch
needs to keep its patch stack without dropping local-only behavior.

## Goal

Every sync should end with:

- `origin/main` fetched to the true latest commit.
- One merge commit whose first parent is the previous local branch and whose
  second parent is the latest upstream commit.
- A small, reviewable `origin/main..HEAD` delta containing only local CtriXin
  behavior.
- The local fix inventory audited by `scripts/check-local-upstream-sync.sh`.
- A tagged DEV build and a DEV `.dmg` for user handoff. App links alone are not
  a complete handoff.

## Current local fix inventory

These surfaces are easy to lose during upstream churn and must be checked after
each sync:

| Surface | Primary marker |
| --- | --- |
| Session-list upstream/provider error red row | `SessionEntry.hasUpstreamError`, `SessionIndexStore.hasUpstreamErrorSignal`, `upstreamErrorRowStroke` |
| Codex rollout-tail error detection | `SessionIndexStore+CodexSQL.swift` calling `fileHasUpstreamErrorSignal` |
| OpenCode completion notifications | `processOpenCodeCompletionNotifications`, `opencode.completion.*` localization keys |
| OpenCode socket-scoped polling | `scopedProcessIDsByPanelKey` in `VaultAgentProcessScanner` |
| Terminal title spinner filtering | `stableTerminalPanelTitle`, `publishableTerminalTitle` |
| Terminal context-menu copy fidelity | `terminalContextMenu.copyRaw`, `terminalContextMenu.copyCleaned`, `TerminalCopyCleaner` |
| Browser external-open button | `browser.openInDefaultBrowser` |
| Notification unread / phone dismissal sync | `TerminalController+MobileNotificationSync.swift` and notification unread indexes |
| DEV build handoff | `scripts/package-dev-dmg.sh`, `docs/dev-build-workflow.md` |

If upstream absorbs one of these fixes, remove that row and update
`scripts/check-local-upstream-sync.sh` in the same commit.

## Recommended sync flow

Start from a clean local branch that already contains the previous local fixes:

```bash
git status --short
git fetch origin +main:refs/remotes/origin/main --tags
git switch -c codex/upstream-sync-$(date +%Y%m%d) <local-branch>
git merge --no-commit origin/main
```

Resolve conflicts by keeping upstream as the base and re-applying only the local
fix inventory. Then run:

```bash
./scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj
./scripts/check-local-upstream-sync.sh origin/main
```

If the merge command cannot produce the desired parent order, create the final
merge commit from the resolved index:

```bash
git commit-tree "$(git write-tree)" -p <previous-local-head> -p origin/main -F /tmp/message.txt
```

Then move the branch with `git update-ref`. The resulting commit should show:

```text
Merge: <previous-local-head> <latest-origin-main>
```

## Validation flow

Use a tag that names the sync:

```bash
TAG=upstream-sync
CMUX_SKIP_ZIG_BUILD=1 xcodebuild test \
  -project cmux.xcodeproj \
  -scheme cmux-unit \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-$TAG" \
  -only-testing:cmuxTests/SessionIndexViewTests

CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag "$TAG"
./scripts/package-dev-dmg.sh --tag "$TAG"
```

`CMUX_SKIP_ZIG_BUILD=1` is only for machines whose Zig version does not match
the repo's required toolchain for rebuilding `cmuxd`. When Zig is correct, omit
that variable.

## Handoff

When handing off to Xin after a sync, always provide the DEV `.dmg`. Do not stop
at the `reload.sh` app link unless the user explicitly says no dmg is needed.

Record:

- latest upstream SHA;
- local merge commit SHA;
- `git diff --shortstat origin/main..HEAD`;
- commands run and pass/fail status;
- tagged app path from `reload.sh`;
- dmg path from `package-dev-dmg.sh`;
- `hdiutil verify` result for the dmg;
- dmg size and SHA-256 checksum;
- a clickable `file://` link to the dmg.

Use Codex app links from the exact `App path:` printed by `reload.sh`; never
invent `/tmp/cmux-<tag>/...` links.
