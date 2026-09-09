#!/bin/bash

set -euo pipefail

# hidden-entries.sh decides which desktop entries the launcher never shows.
# It is run here against a throwaway HOME and a stubbed omarchy-pkg-present,
# so what lands in its output -- and specifically that the upstream Hermes
# launcher is hidden only while the packaged desktop app owns Hermes -- is
# read off the script's actual answer rather than its source.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
user_apps="$test_tmp/home/.local/share/applications"
mkdir -p "$mock_bin" "$user_apps"

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == "hermes-desktop" && ${OMARCHY_TEST_DESKTOP_INSTALLED:-0} == "1" ]]
SH

# The upstream runtime's own launcher entry, as its install writes it.
cat >"$user_apps/hermes.desktop" <<'SH'
[Desktop Entry]
Type=Application
Name=Hermes
Exec=/home/tmo/.local/bin/hermes desktop
SH

# A genuinely hidden entry, to prove the scan still does its old job.
cat >"$user_apps/hidden-helper.desktop" <<'SH'
[Desktop Entry]
Type=Application
Name=Hidden Helper
Exec=/usr/bin/true
Hidden=true
SH

run_scan() {
  # The script's exit code is the last scan_dir's, and an absent
  # ~/.nix-profile answers 1; the shell reads its stdout, not its status.
  OMARCHY_TEST_DESKTOP_INSTALLED="${1:-0}" \
    HOME="$test_tmp/home" \
    PATH="$mock_bin:$PATH" \
    bash "$ROOT/shell/services/hidden-entries.sh" || true
}

chmod +x "$mock_bin"/*

# Package present: the packaged app owns Hermes, so the upstream launcher's
# entry goes the way of every other superseded entry.
run_scan 1 >"$test_tmp/output"
grep -qx hermes "$test_tmp/output" || fail "the Hermes launcher is hidden while the package owns Hermes"
grep -qx hidden-helper "$test_tmp/output" || fail "a Hidden=true entry is still hidden"
pass "the Hermes launcher is hidden while the packaged app owns Hermes"

# Package absent: the runtime's launcher is the only Hermes launcher there is,
# and hiding it would leave the desktop app unreachable from search.
run_scan 0 >"$test_tmp/output"
grep -qx hermes "$test_tmp/output" && fail "the Hermes launcher stays hidden without the package"
grep -qx hidden-helper "$test_tmp/output" || fail "a Hidden=true entry is still hidden without the package"
pass "a Hermes installed without the package stays launchable"
