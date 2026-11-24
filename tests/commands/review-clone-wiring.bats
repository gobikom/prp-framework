#!/usr/bin/env bats
# Static wiring tests for the private review clone (prp-framework#252, PR-B, invariant CLONE-WIRED).
# Every case runs over the canonical prompt and every generated adapter of review-agents
# (gemini's TOML is decoded first, so the checks see the text an agent executes).
#
# Run: bats tests/commands/review-clone-wiring.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
source "$ROOT/tests/helpers/fence.bash"

FILES="
prompts/review-agents.md
adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md
"

# b5 allowlist: STOP/FATAL lines that run before `create` could print a REVIEW_CLONE_ID,
# so there is no clone to clean up. Each entry is a fixed substring of the line, with its reason.
ALLOW=(
  'FATAL: no reviewed head saved by Phase 2.0'   # 2.1.1: before create — no head, no clone
  'FATAL: cannot resolve .prp'                   # 2.1.1: before create — helper not found yet
  'FATAL: cannot check whether .prp is tracked'  # 2.1.1: before create — tracked-.prp guard (also carries the next entry)
  'FATAL: cannot create the review clone'        # 2.1.1: create itself failed — its EXIT trap tombstoned its root, no id printed
)

text() { prompt_text "$ROOT/$1"; }
# line number of the first line starting with <prefix>, in <file>'s text
heading() { text "$1" | awk -v p="$2" 'index($0, p) == 1 {print NR; exit}'; }

@test "every review-agents file the generator writes is covered" {
  local f
  for f in $FILES; do [ -f "$ROOT/$f" ] || { echo "missing $f" >&2; return 1; }; done
  # any other generated review-agents file must be added to FILES
  run bash -c "cd '$ROOT/adapters' && grep -rlF 'review-clone.sh\" create' . | sed 's|^\./|adapters/|' | sort"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") <(printf '%s\n' $FILES | grep '^adapters/' | sort)
}

@test "b1: no git worktree and no hand-made prp-review-clone- path" {
  local f n
  for f in $FILES; do
    ! text "$f" | grep -nF 'git worktree' || { echo "b1: $f mentions git worktree" >&2; return 1; }
    # the one allowed mention is the sentence that forbids making such a path by hand
    n=$(text "$f" | grep -F 'prp-review-clone-' | grep -vcF 'Never create `prp-review-clone-*`' || true)
    [ "$n" -eq 0 ] || { echo "b1: $f carries $n prp-review-clone- path line(s)" >&2; return 1; }
  done
}

@test "b2: review-clone.sh create appears exactly once, inside 2.1.1, before 2.2 dispatch" {
  local f n c h211 h22
  for f in $FILES; do
    n=$(text "$f" | grep -cF 'review-clone.sh" create') || true
    [ "$n" -eq 1 ] || { echo "b2: $f has $n create calls" >&2; return 1; }
    [ "$(text "$f" | grep -cF 'review-clone.sh create')" -eq 0 ] || { echo "b2: $f has an unquoted create call" >&2; return 1; }
    c=$(text "$f" | grep -nF 'review-clone.sh" create' | cut -d: -f1)
    h211=$(heading "$f" '### 2.1.1 '); h22=$(heading "$f" '### 2.2 Core Agents')
    [ -n "$h211" ] && [ -n "$h22" ] && [ "$h211" -lt "$c" ] && [ "$c" -lt "$h22" ] \
      || { echo "b2: $f create at $c, not between 2.1.1 ($h211) and 2.2 ($h22)" >&2; return 1; }
    # and no other heading sits between 2.1.1 and the create call
    [ -z "$(text "$f" | sed -n "$((h211 + 1)),${c}p" | grep -E '^#{2,4} ')" ] || { echo "b2: $f create is not in 2.1.1" >&2; return 1; }
  done
}

@test "b3: 3.0 runs review-clone.sh verify before its cleanup reference" {
  local f h30 h31 v cl
  for f in $FILES; do
    h30=$(heading "$f" '### 3.0 '); h31=$(heading "$f" '### 3.1 ')
    [ -n "$h30" ] && [ -n "$h31" ] || { echo "b3: $f lacks 3.0 or 3.1" >&2; return 1; }
    v=$(text "$f" | sed -n "${h30},${h31}p" | grep -nF 'review-clone.sh" verify {NUMBER} {REVIEW_CLONE_ID} {SAVED_HEAD}' | head -n1 | cut -d: -f1)
    cl=$(text "$f" | sed -n "${h30},${h31}p" | grep -nF 'Clone cleanup' | head -n1 | cut -d: -f1)
    [ -n "$v" ] && [ -n "$cl" ] && [ "$v" -lt "$cl" ] || { echo "b3: $f verify ($v) not before cleanup ($cl) in 3.0" >&2; return 1; }
  done
}

@test "b4: the Clone cleanup block runs remove and has the nothing-created branch" {
  local f body
  for f in $FILES; do
    body=$(text "$f" | awk 'index($0, "### Clone cleanup (every terminal path)") == 1 {f=1; next} f && /^#{2,3} / {exit} f')
    [ -n "$body" ] || { echo "b4: $f has no Clone cleanup block" >&2; return 1; }
    grep -qF 'review-clone.sh" remove {NUMBER} "$REVIEW_CLONE_ID"' <<< "$body" || { echo "b4: $f cleanup lacks remove" >&2; return 1; }
    grep -qF 'echo "review clone: nothing created"' <<< "$body" || { echo "b4: $f cleanup lacks nothing created" >&2; return 1; }
    [ "$(text "$f" | grep -cF '### Clone cleanup (every terminal path)')" -eq 1 ] || { echo "b4: $f has more than one cleanup block" >&2; return 1; }
  done
}

@test "b5: every STOP or FATAL from 2.1.1 to the end of Phase 3 references Clone cleanup or is allowlisted" {
  local f line ok a bad=0
  for f in $FILES; do
    while IFS= read -r line; do
      [[ $line == *"Clone cleanup"* ]] && continue
      ok=0
      for a in "${ALLOW[@]}"; do [[ $line == *"$a"* ]] && { ok=1; break; }; done
      [ "$ok" -eq 1 ] || { echo "b5: $f: $line" >&2; bad=1; }
    done < <(text "$f" | awk 'index($0, "### 2.1.1 ") == 1 {f=1} index($0, "## Phase 4") == 1 {f=0} f && /STOP|FATAL/')
  done
  [ "$bad" -eq 0 ]
}

@test "b5 sees lines: the range holds the 2.1.1, 2.2.0 and 3.0 STOP/FATAL lines" {
  local n
  n=$(text prompts/review-agents.md | awk 'index($0, "### 2.1.1 ") == 1 {f=1} index($0, "## Phase 4") == 1 {f=0} f && /STOP|FATAL/' | grep -c 'Clone cleanup')
  [ "$n" -ge 6 ]
}

@test "b6: the void-pass re-run reuses REVIEW_CLONE and runs no create" {
  local f para
  for f in $FILES; do
    para=$(text "$f" | grep -F 'Re-run that pass ONCE, under a fresh deadline')
    [ "$(printf '%s\n' "$para" | grep -c .)" -eq 1 ] || { echo "b6: $f re-run paragraph not found once" >&2; return 1; }
    grep -qF 'The re-run uses the same `{REVIEW_CLONE}`; never run `create` again' <<< "$para" || { echo "b6: $f re-run does not reuse the clone" >&2; return 1; }
    ! grep -qF 'review-clone.sh' <<< "$para" || { echo "b6: $f re-run calls review-clone.sh" >&2; return 1; }
    text "$f" | grep -qF 'if any pass came back void (a timebox, 2.2.0), do its one re-run now, against the same `{REVIEW_CLONE}`' || { echo "b6: $f 3.0 lacks the re-run-before-cleanup step" >&2; return 1; }
  done
}
