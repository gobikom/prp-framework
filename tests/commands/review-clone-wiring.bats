#!/usr/bin/env bats
# Static wiring tests for the private review clone (prp-framework#252, PR-B, invariant CLONE-WIRED).
# Every case runs over the canonical prompt and every generated adapter of review-agents
# (gemini's TOML is decoded first, so the checks see the text an agent executes).
#
# Clause 3 is checked against a CLOSED MANIFEST of terminal paths: every path after `create`
# has one prose paragraph (outside code fences) that carries the bold directive
# `**Clone cleanup**`, and the number of such paragraphs in [### 2.1.1, ## Phase 4) equals the
# manifest size. A new terminal path therefore turns b7-count or b5' red until it is added here.
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

# The terminal-path manifest: <id>|<anchor>. Each anchor is a fixed substring of exactly one
# prose paragraph, and that paragraph must instruct **Clone cleanup**.
MANIFEST=(
  'P1|If this block prints FATAL, STOP: spawn no agent and post nothing; if it printed a'   # 2.1.1 FATAL after create may have printed an id
  'P2|If this block prints FATAL, STOP: spawn no agent, post nothing, and run'              # 2.2.0 deadline FATAL
  'P3|If the re-run is void too, STOP: the round is incomplete'                             # 2.2.0 second void re-run
  'P4|the sequential review does not use the clone'                                         # 2.4 sequential fallback
  'P5|If `verify` prints FATAL, STOP: the round is incomplete'                              # 3.0 verify FATAL
  'P6|If the check fails, abort the review'                                                 # 3.0 author-check abort
  'P7|Otherwise run **Clone cleanup** now'                                                  # 3.0 normal completion
  'P8|If the create-output check prints FATAL, STOP'                                        # 2.1.1 create-output check FATAL
)

# b5' allowlist: prose paragraphs in the range that stop or fail BEFORE `create` could print a
# REVIEW_CLONE_ID (no clone exists, nothing to clean up). Fixed substrings, each with its reason.
# Empty today: every pre-create FATAL lives inside the 2.1.1 code fence, which prose() drops.
ALLOW=()

# b5' scan: a paragraph that stops, fails, aborts or falls back. Whole words only, so prose such
# as "a stale file from an aborted run" (the 2.3 round gate, not a terminal path) is not a hit.
STOPWORDS='(^|[^[:alpha:]])(STOP|FATAL|ABORT|abort)([^[:alpha:]]|$)|fall back'

text() { prompt_text "$ROOT/$1"; }
# line number of the first line starting with <prefix>, in <file>'s text
heading() { text "$1" | awk -v p="$2" 'index($0, p) == 1 {print NR; exit}'; }

# prose <file> [all] -> one line per prose paragraph: "<first line number><TAB><paragraph text
# joined with spaces>". Fenced blocks are dropped before the blank-line split, so a mention in
# an `echo` never counts. Default range [### 2.1.1, ## Phase 4); `all` scans the whole text.
prose() {
  text "$1" | awk -v all="${2:-}" '
    function flush() { if (p != "") print s "\t" p; p = "" }
    all != "" {r = 1}
    index($0, "### 2.1.1 ") == 1 {r = 1}
    index($0, "## Phase 4") == 1 && all == "" {flush(); r = 0}
    /^[[:space:]]*```/ {fz = !fz; flush(); next}
    fz || !r || $0 ~ /^[[:space:]]*$/ {flush(); next}
    {if (p == "") {s = NR; p = $0} else p = p " " $0}
    END {flush()}'
}

# start line of the single range paragraph carrying <anchor> (empty unless exactly one)
anchor_line() { prose "$1" | awk -F '\t' -v a="$2" 'index($2, a) {n++; l = $1} END {if (n == 1) print l}'; }

# the 3.0 author-check fence: the bash fence in 3.0 that prints REVIEW ABORT
author_fence() {
  text "$1" | awk 'index($0, "### 3.0 ") == 1 {f = 1} index($0, "### 3.1 ") == 1 {exit}
    f && /^```bash$/ {b = 1; buf = ""; next}
    f && b && /^```$/ {b = 0; if (buf ~ /REVIEW ABORT/) {printf "%s", buf; exit}; next}
    f && b {buf = buf $0 "\n"}'
}

@test "every review-agents file the generator writes is covered" {
  local f
  for f in $FILES; do [ -f "$ROOT/$f" ] || { echo "missing $f" >&2; return 1; }; done
  # any other generated review-agents file must be added to FILES
  run bash -c "cd '$ROOT/adapters' && grep -rlF 'review-clone.sh\" create' . | sed 's|^\./|adapters/|' | sort"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") <(printf '%s\n' $FILES | grep '^adapters/' | sort)
}

@test "prose() sees the range: paragraphs exist, fences are dropped" {
  local f n
  for f in $FILES; do
    n=$(prose "$f" | grep -c .) || true
    [ "$n" -ge 20 ] || { echo "prose: $f yields $n paragraphs" >&2; return 1; }
    ! prose "$f" | grep -qF 'review-clone.sh" create' || { echo "prose: $f kept a fenced line" >&2; return 1; }
  done
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

@test "b3: in 3.0 the verify fence closes before P5, P6 and P7, and P7 comes last" {
  local f h30 h31 vend p5 p6 p7
  for f in $FILES; do
    h30=$(heading "$f" '### 3.0 '); h31=$(heading "$f" '### 3.1 ')
    [ -n "$h30" ] && [ -n "$h31" ] || { echo "b3: $f lacks 3.0 or 3.1" >&2; return 1; }
    # closing line of the fence that runs verify
    vend=$(text "$f" | awk -v a="$h30" -v z="$h31" 'NR > a && NR < z && /^```bash$/ {b = 1; v = 0; next}
      NR > a && NR < z && b && /^```$/ {b = 0; if (v) {print NR; exit}; next}
      b && index($0, "review-clone.sh\" verify {NUMBER} {REVIEW_CLONE_ID} {SAVED_HEAD}") {v = 1}')
    p5=$(anchor_line "$f" 'If `verify` prints FATAL, STOP: the round is incomplete')
    p6=$(anchor_line "$f" 'If the check fails, abort the review')
    p7=$(anchor_line "$f" 'Otherwise run **Clone cleanup** now')
    [ -n "$vend" ] && [ -n "$p5" ] && [ -n "$p6" ] && [ -n "$p7" ] || { echo "b3: $f verify end ($vend) or P5/P6/P7 ($p5/$p6/$p7) missing" >&2; return 1; }
    [ "$h30" -lt "$vend" ] && [ "$vend" -lt "$p5" ] && [ "$vend" -lt "$p6" ] && [ "$p5" -lt "$p7" ] && [ "$p6" -lt "$p7" ] && [ "$p7" -lt "$h31" ] \
      || { echo "b3: $f order wrong: verify end $vend, P5 $p5, P6 $p6, P7 $p7 (3.0 $h30..$h31)" >&2; return 1; }
  done
}

@test "b4: the Clone cleanup block runs remove and has the nothing-created branch" {
  local f body
  for f in $FILES; do
    body=$(text "$f" | awk 'index($0, "### Clone cleanup (every terminal path)") == 1 {f=1; next} f && /^###? / {exit} f')
    [ -n "$body" ] || { echo "b4: $f has no Clone cleanup block" >&2; return 1; }
    grep -qF 'review-clone.sh" remove {NUMBER} "$REVIEW_CLONE_ID"' <<< "$body" || { echo "b4: $f cleanup lacks remove" >&2; return 1; }
    grep -qF 'echo "review clone: nothing created"' <<< "$body" || { echo "b4: $f cleanup lacks nothing created" >&2; return 1; }
    [ "$(text "$f" | grep -cF '### Clone cleanup (every terminal path)')" -eq 1 ] || { echo "b4: $f has more than one cleanup block" >&2; return 1; }
  done
}

@test "b5': every prose paragraph that stops, fails, aborts or falls back is a manifest entry or allowlisted" {
  local f para e a ok bad=0
  for f in $FILES; do
    while IFS= read -r para; do
      ok=0
      for e in "${MANIFEST[@]}"; do [[ $para == *"${e#*|}"* ]] && { ok=1; break; }; done
      for a in "${ALLOW[@]}"; do [[ $para == *"$a"* ]] && { ok=1; break; }; done
      [ "$ok" -eq 1 ] || { echo "b5': $f: unlisted terminal paragraph: $para" >&2; bad=1; }
    done < <(prose "$f" | grep -E "$STOPWORDS")
  done
  [ "$bad" -eq 0 ]
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

@test "b7: each manifest anchor is in exactly one prose paragraph, and it instructs **Clone cleanup**" {
  local f e id anchor hits
  for f in $FILES; do
    for e in "${MANIFEST[@]}"; do
      id=${e%%|*}; anchor=${e#*|}
      hits=$(prose "$f" | awk -F '\t' -v a="$anchor" 'index($2, a)' )
      [ "$(printf '%s' "$hits" | grep -c .)" -eq 1 ] || { echo "b7: $f $id anchor not in exactly one prose paragraph" >&2; return 1; }
      grep -qF '**Clone cleanup**' <<< "$hits" || { echo "b7: $f $id paragraph does not instruct **Clone cleanup**" >&2; return 1; }
    done
  done
}

@test "b7-count: prose paragraphs carrying **Clone cleanup** in [2.1.1, Phase 4) == manifest size" {
  local f n
  for f in $FILES; do
    n=$(prose "$f" | grep -cF '**Clone cleanup**') || true
    [ "$n" -eq "${#MANIFEST[@]}" ] || { echo "b7-count: $f has $n cleanup paragraphs, manifest has ${#MANIFEST[@]}" >&2; return 1; }
  done
}

@test "b8: every \$NAME the 3.0 author-check fence reads is assigned inside that fence" {
  local f body name bad=0
  for f in $FILES; do
    body=$(author_fence "$f")
    [ -n "$body" ] || { echo "b8: $f has no 3.0 author-check fence" >&2; return 1; }
    grep -qF "AUTHOR_HEAD='{AUTHOR_HEAD}'" <<< "$body" || { echo "b8: $f fence does not start from the 2.1.1 placeholders" >&2; return 1; }
    for name in $(grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' <<< "$body" | tr -d '${' | sort -u); do
      grep -qE "(^|[;[:space:]])${name}=" <<< "$body" || { echo "b8: $f reads \$$name without assigning it" >&2; bad=1; }
    done
  done
  [ "$bad" -eq 0 ]
}

@test "b9: 2.1.1 checks create's output, and its FATAL is manifest entry P8" {
  local f body
  for f in $FILES; do
    body=$(fence "$ROOT/$f" "### 2.1.1 ")
    grep -qF 'CREATE_OUT=$(bash "$PRP_DIR/scripts/review/review-clone.sh" create' <<< "$body" || { echo "b9: $f does not capture create's output" >&2; return 1; }
    grep -qF "grep -c '^REVIEW_CLONE=/')\" -eq 1" <<< "$body" || { echo "b9: $f lacks the one-REVIEW_CLONE check" >&2; return 1; }
    grep -qF "grep -cxE 'REVIEW_CLONE_ID=[A-Za-z0-9]{10}')\" -eq 1" <<< "$body" || { echo "b9: $f lacks the one-REVIEW_CLONE_ID check" >&2; return 1; }
    grep -qF 'FATAL: create did not print exactly one REVIEW_CLONE= and one REVIEW_CLONE_ID= line' <<< "$body" || { echo "b9: $f lacks the create-output FATAL" >&2; return 1; }
  done
  printf '%s\n' "${MANIFEST[@]}" | grep -qxF 'P8|If the create-output check prints FATAL, STOP'
}

@test "b10: the verify FATAL (P5) posts nothing and emits no L2 marker" {
  local f para
  for f in $FILES; do
    para=$(prose "$f" | grep -F 'If `verify` prints FATAL, STOP: the round is incomplete')
    [ -n "$para" ] || { echo "b10: $f has no P5 paragraph" >&2; return 1; }
    grep -qF 'post nothing' <<< "$para" || { echo "b10: $f P5 lacks post nothing" >&2; return 1; }
    grep -qF 'emit no L2 marker' <<< "$para" || { echo "b10: $f P5 lacks emit no L2 marker" >&2; return 1; }
  done
}

@test "b11: agents get {REVIEW_CLONE}, and no prose names a bare \$REVIEW_CLONE" {
  local f
  for f in $FILES; do
    prose "$f" | grep -qF 'Pass `{REVIEW_CLONE}` (not `$AUTHOR_WORKTREE`) to every agent prompt' || { echo "b11: $f lacks the Pass {REVIEW_CLONE} instruction" >&2; return 1; }
    ! prose "$f" all | grep -E '\$REVIEW_CLONE([^_]|$)' || { echo "b11: $f prose names a bare \$REVIEW_CLONE" >&2; return 1; }
  done
}
