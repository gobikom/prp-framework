### 2.0c Start the L2 Run (`--l2-comments` only, SO#1367 Rule E)

Invariant: an `--l2-comments` run posts exactly **one start comment before any agent starts**, and its run id is the one every pass comment of the run carries. The comment's server `created_at` is when the round began. Nothing reads it yet. Once SO#1367 Rule E is in merger's policy, a round counts only when its start comment is older than its pass comments and the head did not move in between. Readers that select pass comments by line 1 `Reviewed head:` (safe-merge, the L2 recipe) never select it: its line 1 is `Review started:`.

Run it in every `--l2-comments` run, right after 2.0b and before 2.1.1. Without `--l2-comments`, run nothing here. If it prints FATAL, STOP: start no agent. A start comment that was posted for a run that then stops is harmless; the next run posts its own.

**Step A — start the run** (clears any earlier run's files, reads the reviewed head saved in Phase 2.0, draws `RUN_ID`, posts the start comment, then saves the run values for Steps B and C):

```bash
D=.prp-output/reviews
rm -f "$D/pr-{NUMBER}-l2-run.env" "$D/pr-{NUMBER}-l2-run.env.used" "$D"/pr-{NUMBER}-l2-*-reviewer.md "$D/pr-{NUMBER}-l2-silent-failure-hunter.md" "$D/pr-{NUMBER}-l2-start.md"
REVIEWED_HEAD_SHA=$(cat "$D/pr-{NUMBER}-reviewed-head" 2>/dev/null) || REVIEWED_HEAD_SHA=""
[ ${#REVIEWED_HEAD_SHA} -eq 40 ] && printf '%s' "$REVIEWED_HEAD_SHA" | grep -qxE '[0-9a-f]{40}' || { echo "FATAL: no reviewed head saved by Phase 2.0 ($D/pr-{NUMBER}-reviewed-head) — re-run the review from Phase 2.0 and every agent after it (the head is captured before the agents, never at posting time)" >&2; exit 1; }
[ -L .prp ] || { echo "FATAL: .prp is not a symlink to the installed prp-framework — no comments posted" >&2; exit 1; }
PRP_DIR=$(readlink -f .prp) || { echo "FATAL: cannot resolve .prp" >&2; exit 1; }
PRP_VERSION=$(git -C "$PRP_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null) || { echo "FATAL: cannot read the prp-framework release tag — no comments posted" >&2; exit 1; }
PRP_VERSION="${PRP_VERSION#v}"   # the latest release tag reachable from the installed framework; the footer adds the v
printf '%s' "$PRP_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' || { echo "FATAL: release tag '$PRP_VERSION' is not a version" >&2; exit 1; }
RAND=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n') && [ ${#RAND} -eq 8 ] || { echo "FATAL: cannot draw a run id" >&2; exit 1; }
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RAND"
TIER=$(cat "$D/pr-{NUMBER}-tier" 2>/dev/null) || TIER=""
case "$TIER" in trivial|standard) ;; *) echo "FATAL: no tier saved by 2.0b ($D/pr-{NUMBER}-tier) — run 2.0b, then the agents" >&2; exit 1 ;; esac
NOW_HEAD=$(gh pr view {NUMBER} --json headRefOid -q .headRefOid) || { echo "FATAL: cannot read the PR head (gh failed) — no start comment, no agents started" >&2; exit 1; }
[ "$NOW_HEAD" = "$REVIEWED_HEAD_SHA" ] || { echo "FATAL: PR head moved ($REVIEWED_HEAD_SHA -> $NOW_HEAD) — re-run from Phase 2.0, no start comment, no agents started" >&2; exit 1; }
printf 'Review started: head=%s run=%s\nGenerated-by: prp-review-agents v%s run=%s pass=start\n' "$REVIEWED_HEAD_SHA" "$RUN_ID" "$PRP_VERSION" "$RUN_ID" > "$D/pr-{NUMBER}-l2-start.md" || { echo "FATAL: cannot write the start comment" >&2; exit 1; }
START_URL=$(gh pr comment {NUMBER} --body-file "$D/pr-{NUMBER}-l2-start.md") || { echo "FATAL: posting the start comment failed — no agents started; re-run Step A" >&2; exit 1; }
printf '%s' "$START_URL" | grep -qxE 'https://github\.com/[^ ]+#issuecomment-[0-9]+' || { echo "FATAL: the start comment post returned no comment URL ('$START_URL') — no agents started; re-run Step A" >&2; exit 1; }
# written only after the start comment is up: without it there is no run file, so Step C posts nothing
printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=%s\nRUN_ID=%s\nTIER=%s\nSTART_URL=%s\n' "$REVIEWED_HEAD_SHA" "$PRP_VERSION" "$RUN_ID" "$TIER" "$START_URL" > "$D/pr-{NUMBER}-l2-run.env" || { echo "FATAL: cannot save the run file — no agents started" >&2; exit 1; }
cat "$D/pr-{NUMBER}-l2-run.env"
```

