D=.prp-output/reviews
rm -f "$D/pr-7-l2-run.env" "$D/pr-7-l2-run.env.used" "$D"/pr-7-l2-*-reviewer.md "$D/pr-7-l2-silent-failure-hunter.md"
REVIEWED_HEAD_SHA=$(cat "$D/pr-7-reviewed-head" 2>/dev/null) || REVIEWED_HEAD_SHA=""
[ ${#REVIEWED_HEAD_SHA} -eq 40 ] && printf '%s' "$REVIEWED_HEAD_SHA" | grep -qxE '[0-9a-f]{40}' || { echo "FATAL: no reviewed head saved by Phase 2.0 ($D/pr-7-reviewed-head) — re-run the review from Phase 2.0 and every agent after it (the head is captured before the agents, never at posting time)" >&2; exit 1; }
[ -L .prp ] || { echo "FATAL: .prp is not a symlink to the installed prp-framework — no comments posted" >&2; exit 1; }
PRP_DIR=$(readlink -f .prp) || { echo "FATAL: cannot resolve .prp" >&2; exit 1; }
PRP_VERSION=$(git -C "$PRP_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null) || { echo "FATAL: cannot read the prp-framework release tag — no comments posted" >&2; exit 1; }
PRP_VERSION="${PRP_VERSION#v}"   # the latest release tag reachable from the installed framework; the footer adds the v
printf '%s' "$PRP_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' || { echo "FATAL: release tag '$PRP_VERSION' is not a version" >&2; exit 1; }
RAND=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n') && [ ${#RAND} -eq 8 ] || { echo "FATAL: cannot draw a run id" >&2; exit 1; }
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RAND"
TIER=$(cat "$D/pr-7-tier" 2>/dev/null) || TIER=""
case "$TIER" in trivial|standard) ;; *) echo "FATAL: no tier saved by 2.0b ($D/pr-7-tier) — run 2.0b, then the agents" >&2; exit 1 ;; esac
printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=%s\nRUN_ID=%s\nTIER=%s\n' "$REVIEWED_HEAD_SHA" "$PRP_VERSION" "$RUN_ID" "$TIER" > "$D/pr-7-l2-run.env" || { echo "FATAL: cannot save the run file" >&2; exit 1; }
cat "$D/pr-7-l2-run.env"
