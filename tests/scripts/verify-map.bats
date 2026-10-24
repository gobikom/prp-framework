#!/usr/bin/env bats
# Tests for scripts/prp-verify-map.sh (#202 PR-B, plan Tasks B2/B3).
#
# Requirements: bats-core, git, python3 + PyYAML
# Run: bats tests/scripts/verify-map.bats
#
# Every test builds its own throwaway git repo in BATS_TMPDIR with
# core.hooksPath=/dev/null and a fixed GIT_* identity, so no test touches
# the host's hooks or identity.

VM="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/prp-verify-map.sh"
FIX="$(cd "$(dirname "$BATS_TEST_FILENAME")/fixtures/verify-map" && pwd)"

GITC=(git -c core.hooksPath=/dev/null -c user.email=t@example.com -c user.name=tester)

setup() {
    REPO="$BATS_TMPDIR/verify-map-$$-$_"
    mkdir -p "$REPO"
    cd "$REPO" || exit 1
    "${GITC[@]}" init -q
    "${GITC[@]}" checkout -q -b main
    "${GITC[@]}" commit -q --allow-empty -m init
    mkdir -p src/lib docs
    echo "alpha body" > src/lib/alpha.py
    echo "x content" > docs/x.md
    "${GITC[@]}" add -A
    "${GITC[@]}" commit -q -m files
    HEAD_SHA="$("${GITC[@]}" rev-parse HEAD)"
    sed "s/__SHA__/$HEAD_SHA/g" "$FIX/good.yaml" > verify-map.yaml
}

teardown() {
    cd / || true
    rm -rf "$REPO"
}

commit_change() {
    echo "$1" >> src/lib/alpha.py
    "${GITC[@]}" commit -qam "$1"
}

@test "script is executable with a bash shebang" {
    [ -x "$VM" ]
    head -1 "$VM" | grep -qE '#!.*bash'
}

@test "usage without args exits 2 and prints the exit contract" {
    run bash "$VM"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Exit contract"* ]]
}

@test "B13: PATH without git exits 3" {
    run env PATH="$(mktemp -d)" /bin/bash "$VM" validate verify-map.yaml
    [ "$status" -eq 3 ]
}

@test "validate: good map exits 0" {
    run bash "$VM" validate verify-map.yaml
    [ "$status" -eq 0 ]
}

@test "B8: each invalid fixture exits 1 with a message" {
    for f in "$FIX"/invalid-*.yaml; do
        run bash "$VM" validate "$f"
        if [ "$status" -ne 1 ]; then
            fail "$(basename "$f"): expected exit 1, got $status (output: $output)"
        fi
        [ -n "$output" ]
    done
}

@test "validate: missing map file exits 3" {
    run bash "$VM" validate "$REPO/nope.yaml"
    [ "$status" -eq 3 ]
}

@test "B2: stale at the synced sha prints nothing and exits 0" {
    run bash "$VM" stale verify-map.yaml
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B2: stale after a paths change prints the stale id" {
    commit_change touch
    run bash "$VM" stale verify-map.yaml
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha-smoke"* ]]
    [[ "$output" == *"vacuous-one"* ]]
    [[ "$output" != *"docs-neg"* ]]
}

@test "B2: unknown synced_sha exits 3" {
    sed -i "s/$HEAD_SHA/1111111111111111111111111111111111111111/g" verify-map.yaml
    run bash "$VM" stale verify-map.yaml
    [ "$status" -eq 3 ]
}

@test "B2: match prints live ids; no hit prints nothing" {
    run bash "$VM" match verify-map.yaml "the alpha flow"
    [ "$status" -eq 0 ]
    [[ "$output" == *"live:alpha-smoke"* ]]
    run bash "$VM" match verify-map.yaml "nothing matches here zzz"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "B4: run passes when expect is met" {
    run bash "$VM" run verify-map.yaml alpha-smoke
    [ "$status" -eq 0 ]
    [[ "$output" == *"map:alpha-smoke exit=0"* ]]
}

@test "B4: run fails with evidence when stdout_regex misses" {
    sed -i 's/exit: 0/exit: 0\n      stdout_regex: "zzz-never"/' verify-map.yaml
    run bash "$VM" run verify-map.yaml alpha-smoke
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL map:alpha-smoke"* ]]
    [[ "$output" == *"stdout does not match"* ]]
}

@test "B2: run with an unknown id exits 2" {
    run bash "$VM" run verify-map.yaml no-such-id
    [ "$status" -eq 2 ]
}

@test "B9: exercise past its timeout fails with the timeout reason" {
    sed -e 's/id: alpha-smoke/id: slow-one/' \
        -e 's/exercise: grep -q alpha src\/lib\/alpha.py/exercise: sleep 5/' \
        -e 's/timeout: 10/timeout: 1/' verify-map.yaml > slow.yaml
    run bash "$VM" run slow.yaml slow-one
    [ "$status" -eq 1 ]
    [[ "$output" == *"timeout after 1s"* ]]
}

@test "B4: uat with no PRP_VERIFY_UAT_URL exits 4 UNVERIFIED" {
    sed -e 's/env: local/env: uat/' -e '/id: alpha-smoke/s//id: uat-one/' verify-map.yaml > uat.yaml
    run bash "$VM" run uat.yaml uat-one
    [ "$status" -eq 4 ]
    [[ "$output" == *"UNVERIFIED"* ]]
}

@test "B4: creds var unset exits 4 without echoing any value" {
    unset MY_SECRET_TOKEN || true
    sed -e 's/env: local/env: creds:MY_SECRET_TOKEN/' \
        -e '/id: alpha-smoke/s//id: cred-one/' verify-map.yaml > cred.yaml
    run bash "$VM" run cred.yaml cred-one
    [ "$status" -eq 4 ]
    [[ "$output" == *"MY_SECRET_TOKEN not set"* ]]
}

@test "B12: prove-negative refuses a trivially true exercise" {
    run bash "$VM" prove-negative verify-map.yaml vacuous-one
    [ "$status" -eq 1 ]
    [[ "$output" == *"vacuous: trivial exercise"* ]]
}

@test "B12: prove-negative refuses an exercise inside paths" {
    run bash "$VM" prove-negative verify-map.yaml alpha-smoke
    [ "$status" -eq 1 ]
    [[ "$output" == *"paths include the exercise"* ]]
}

@test "B12: prove-negative holds when the exercise fails without its paths" {
    run bash "$VM" prove-negative verify-map.yaml docs-neg
    [ "$status" -eq 0 ]
    [[ "$output" == *"negative held exit="* ]]
}

@test "B12: prove-negative flags vacuous when expect still met after deletion" {
    # exercise ignores the paths entirely, so it still passes after deletion
    sed -e '/id: alpha-smoke/s//id: blind-one/' \
        -e 's/exercise: grep -q alpha src\/lib\/alpha.py/exercise: printf "unaffected\\n"/' verify-map.yaml > blind.yaml
    run bash "$VM" prove-negative blind.yaml blind-one
    [ "$status" -eq 1 ]
    [[ "$output" == *"vacuous: negative proof met expect"* ]]
}

@test "B5: sync stale-then-pass advances synced_sha (--write)" {
    commit_change touch
    run bash "$VM" sync verify-map.yaml docs-neg --write
    [ "$status" -eq 0 ]
    NEW_SHA="$("${GITC[@]}" rev-parse HEAD)"
    grep -q "synced_sha: $NEW_SHA" verify-map.yaml
    # the entry's paths did not change, but sync sets synced_sha to HEAD
    run bash "$VM" stale verify-map.yaml
    [[ "$output" != *"docs-neg"* ]]
}

@test "B5: sync stale-then-fail leaves the map byte-identical" {
    commit_change touch
    # expect exit 7 while the exercise exits 0 -> run fails -> sync refuses
    sed -e '/id: alpha-smoke/s//id: failing-one/' \
        -e '/exit: 0/s//exit: 7/' verify-map.yaml > failing.yaml
    cp failing.yaml failing-before.yaml
    run bash "$VM" sync failing.yaml failing-one --write
    [ "$status" -eq 1 ]
    cmp -s failing-before.yaml failing.yaml
}

@test "B5: rewritten exercise then sync passes" {
    # the original exercise cannot hold a negative proof for its paths; the
    # rewrite retargets exercise AND paths to a provable pair, then sync passes
    sed -e '/id: alpha-smoke/s//id: rewritten/' verify-map.yaml > rw.yaml
    run bash "$VM" sync rw.yaml rewritten --write
    [ "$status" -eq 1 ]  # vacuous negative proof -> refused
    sed -i -e 's/exercise: grep -q alpha src\/lib\/alpha.py/exercise: ls docs | grep -q x/' \
           -e 's|paths: \["src/lib/\*\*"\]|paths: ["docs/**"]|' rw.yaml
    run bash "$VM" sync rw.yaml rewritten --write
    [ "$status" -eq 0 ]
}

@test "B6: sync with all paths deleted tombstones the entry" {
    "${GITC[@]}" rm -q -r docs
    "${GITC[@]}" commit -qm "delete docs"
    run bash "$VM" sync verify-map.yaml docs-neg --write
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed:docs-neg"* ]]
    grep -q 'id: docs-neg' verify-map.yaml
    grep -q 'paths deleted at' verify-map.yaml
    ! grep -q 'summary: docs listing' verify-map.yaml
    run bash "$VM" match verify-map.yaml "docs flow"
    [[ "$output" == *"removed:docs-neg"* ]]
}

@test "a worktree-mutating exercise fails with exit 1" {
    sed -e '/id: alpha-smoke/s//id: mutator/' \
        -e 's/exercise: grep -q alpha src\/lib\/alpha.py/exercise: touch side-effect.txt/' verify-map.yaml > mut.yaml
    run bash "$VM" run mut.yaml mutator
    [ "$status" -eq 1 ]
    [[ "$output" == *"exercise mutated worktree"* ]]
    rm -f side-effect.txt
}

@test "sync with an unknown id exits 2" {
    run bash "$VM" sync verify-map.yaml no-such-id
    [ "$status" -eq 2 ]
}

@test "stale with a stray positional exits 2" {
    run bash "$VM" stale verify-map.yaml HEAD~1
    [ "$status" -eq 2 ]
}

@test "stale --head <ref> is accepted" {
    run bash "$VM" stale verify-map.yaml --head HEAD
    [ "$status" -eq 0 ]
}

@test "run returns 3 when the judge fails on an invalid regex" {
    sed -e 's/^      exit: 0/      exit: 0\n      stdout_regex: "([a-"/' verify-map.yaml > badre.yaml
    run bash "$VM" run badre.yaml alpha-smoke
    [ "$status" -eq 3 ]
}

@test "prove-negative with an unavailable env exits 4 (no false negative held)" {
    sed -e 's/env: local/env: uat/' -e '/id: alpha-smoke/s//id: uat-one/' verify-map.yaml > uatpn.yaml
    run bash "$VM" prove-negative uatpn.yaml uat-one
    [ "$status" -eq 4 ]
}

@test "prove-negative returns 3 when the judge fails (never a proven negative)" {
    # docs-neg: exercise does not word-match its paths, so the judge is reached
    sed -e 's/^      exit: 0/      exit: 0\n      stdout_regex: "([a-"/' verify-map.yaml > badre2.yaml
    run bash "$VM" prove-negative badre2.yaml docs-neg
    [ "$status" -eq 3 ]
}

@test "sync propagates exit 4 (env unavailable) and leaves the map byte-identical" {
    sed -e 's/env: local/env: uat/' -e '/id: alpha-smoke/s//id: uat-one/' verify-map.yaml > uatsync.yaml
    cp uatsync.yaml uatsync.bak
    run bash "$VM" sync uatsync.yaml uat-one
    [ "$status" -eq 4 ]
    cmp uatsync.yaml uatsync.bak
}

@test "sync propagates exit 3 (judge tool error) and leaves the map byte-identical" {
    sed -e 's/^      exit: 0/      exit: 0\n      stdout_regex: "([a-"/' verify-map.yaml > badre3.yaml
    cp badre3.yaml badre3.bak
    run bash "$VM" sync badre3.yaml alpha-smoke
    [ "$status" -eq 3 ]
    cmp badre3.yaml badre3.bak
}

@test "run is cwd-independent (exercise runs from the repo root)" {
    mkdir -p src/lib/deeper
    cd src/lib/deeper
    run bash "$VM" run "$(cd ../../.. && pwd)/verify-map.yaml" alpha-smoke
    [ "$status" -eq 0 ]
}

@test "sync propagates exit 4 from the negative-proof stage" {
    # one-shot server answers the run-stage env probe, then closes: the
    # negative-proof stage's probe fails -> prove_negative returns 4 -> sync 4
    python3 - <<'EOF' > port.txt &
import socketserver, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *a):
        pass
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.handle_request()
srv.server_close()
EOF
    SERV_PID=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s port.txt ] && break; sleep 0.2; done
    PORT=$(cat port.txt)
    python3 -c "
import yaml
m = yaml.safe_load(open('verify-map.yaml'))
for e in m['features']:
    if e['id'] == 'docs-neg':
        e['env'] = 'uat'
yaml.safe_dump(m, open('pnmix.yaml', 'w'), sort_keys=False)
"
    cp pnmix.yaml pnmix.bak
    PRP_VERIFY_UAT_URL="http://127.0.0.1:$PORT/" run bash "$VM" sync pnmix.yaml docs-neg
    kill "$SERV_PID" 2>/dev/null || true
    [ "$status" -eq 4 ]
    cmp pnmix.yaml pnmix.bak
}

@test "validate rejects a tombstone with unknown keys or a bad match" {
    python3 - <<'EOF' > badtomb.yaml
import yaml
m = yaml.safe_load(open("verify-map.yaml"))
m["features"] = []
m["removed"] = [{
    "id": "gone-bad", "bogus_extra": 1, "match": 42,
    "removed_reason": "removed for the tombstone check test",
    "removed_sha": "a" * 40,
}]
yaml.safe_dump(m, open("badtomb.yaml", "w"), sort_keys=False)
EOF
    run bash "$VM" validate badtomb.yaml
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown keys ['bogus_extra']"* ]]
    [[ "$output" == *"match must be a non-empty string list"* ]]
}
