#!/usr/bin/env bash
# Pass timebox for prp-review-agents (prp-framework#151 AC2).
#
# Invariant: a probe started through `run` never outlives its deadline (it is killed at the
# deadline, and not started at all after it), and a pass body that mentions a timebox in any form is
# only postable with a `Follow-up:` issue link (`check-body`). The deadline is an absolute epoch
# minted once per round by `deadline`; there is no state file, and agents cannot widen it.
# Unknown inputs refuse (exit 2): nothing here ever runs a command it could not bound.
#
# usage: pass-budget.sh deadline                 print epoch = now + ${PRP_PASS_BUDGET_SECS:-1200}
#        pass-budget.sh remaining <epoch>        print seconds left; exit 1 when expired
#        pass-budget.sh run <epoch> -- cmd...    bounded run; exit 124 = cut/not started (PASS-TIMEBOXED)
#        pass-budget.sh check-body <file>        exit 1 if the body mentions a timebox without
#                                                a `Follow-up: https://github.com/<o>/<r>/issues/<n>` line
# exit 2 = usage error / bad value / no `timeout` command / body over the size cap / not valid UTF-8.
# Note: exit 124 from `run` also covers a command that itself exits 124.
set -euo pipefail

DEFAULT_SECS=1200
MAX_SECS=14400
CHECK_BODY_MAX_BYTES=65536  # 64 KiB; plenty for a pass body — refuse anything bigger before normalising

die() { echo "error: $*" >&2; exit 2; }

num() { # num <value> <pattern> <what>
  # Anchor against the WHOLE string via bash's own =~ (no per-line match): piping through
  # `grep -qxE` matched if ANY one line of a multi-line value was all-digits, letting a
  # payload like $'9999999999\n+DEFAULT_SECS[$(cmd)]' pass this gate and then run as a
  # command inside the caller's `$((10#$1 ...))` arithmetic (prp#151 round-5 security finding).
  [[ "$1" =~ ^($2)$ ]] || die "$3 must match $2"
}

epoch_arg() { num "${1:-}" '[0-9]{10}' "epoch"; }

timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then echo timeout
  elif command -v gtimeout >/dev/null 2>&1; then echo gtimeout
  else die "no timeout command (timeout/gtimeout) — refusing to run an unbounded probe"; fi
}

[[ $# -ge 1 ]] || die "usage: pass-budget.sh deadline|remaining|run|check-body"
SUB="$1"; shift

case "$SUB" in
  deadline)
    secs="${PRP_PASS_BUDGET_SECS-$DEFAULT_SECS}"
    num "$secs" '[0-9]{1,5}' "PRP_PASS_BUDGET_SECS"
    secs=$((10#$secs))
    (( secs >= 1 && secs <= MAX_SECS )) || die "PRP_PASS_BUDGET_SECS must be 1..$MAX_SECS"
    echo $(( $(date +%s) + secs ))
    ;;
  remaining)
    epoch_arg "${1:-}"
    left=$(( 10#$1 - $(date +%s) ))
    if (( left <= 0 )); then echo 0; exit 1; fi
    echo "$left"
    ;;
  run)
    epoch_arg "${1:-}"
    epoch=$((10#$1)); shift
    [[ "${1:-}" == "--" ]] || die "run needs: <epoch> -- cmd..."
    shift
    [[ $# -ge 1 ]] || die "run needs a command after --"
    T=$(timeout_cmd)
    left=$(( epoch - $(date +%s) ))
    if (( left <= 0 )); then
      echo "PASS-TIMEBOXED: deadline passed, probe not started: $1" >&2
      exit 124
    fi
    # Give the probe private, file-backed stdout/stderr instead of letting it inherit ours.
    # `timeout` only reaps its own direct child; a probe that detaches a grandchild (setsid)
    # survives past the deadline, and if that grandchild held our REAL stdout, a caller doing
    # `out=$(pass-budget.sh run ...)` would block on that orphan's exit — the deadline we just
    # enforced would not bound the caller's own wait (reproduced: 2s deadline, 9s actual return,
    # prp#151 round-5 security finding). A file is never held open for a reader, so `timeout`
    # returning is enough to let us `cat` it back and exit immediately; the orphan may still run
    # in the background (tracked as a residual limitation, not a hang, in the follow-up issue).
    # Two assignments on one line would hide a failure of the FIRST substitution: bash's `set -e`
    # only inspects the exit status of the LAST command substitution on an assignment-only line,
    # so `out=$(mktemp) err=$(mktemp)` with a failing first mktemp would leave $out empty and
    # silently continue (round-6 silent-failure-hunter finding). Separate lines + explicit `die`
    # make a tmpdir failure a clear diagnosis instead of a confusing downstream `cat`/redirect error.
    out=$(mktemp) || die "run: could not create temp file for probe stdout"
    trap 'rm -f "$out" "${err:-}"' EXIT
    err=$(mktemp) || die "run: could not create temp file for probe stderr"
    rc=0
    "$T" --kill-after=5 "$left" "$@" >"$out" 2>"$err" || rc=$?
    cat "$out"
    cat "$err" >&2
    if (( rc == 124 || rc == 137 )); then
      echo "PASS-TIMEBOXED: probe cut at the deadline: $1" >&2
      exit 124
    fi
    exit "$rc"
    ;;
  check-body)
    f="${1:-}"
    [[ -n "$f" && -r "$f" && -f "$f" && ! -L "$f" ]] || die "check-body needs a readable regular file"
    # Fail closed before normalising: a body over the cap, or not valid UTF-8, never reaches
    # NFKC/regex — that is what let a 20 MB malformed-UTF-8 body hang perl for ~58 min (prp#151 incident).
    size=$(wc -c < "$f") || die "check-body could not stat $f"
    (( size <= CHECK_BODY_MAX_BYTES )) \
      || die "check-body body is $size bytes, over the $CHECK_BODY_MAX_BYTES-byte cap — refusing to normalise"
    # Invariant: any mention of a timebox needs the Follow-up link. Normalise (NFKC, no CR, Unicode spaces
    # to ASCII space, zero-width removed, lowercase) and look for the word anywhere: never at line shape.
    command -v perl >/dev/null 2>&1 || die "check-body needs perl to normalise the body"
    verdict=$(perl -MEncode -MUnicode::Normalize -e '
      local $/;
      open(my $fh, "<:raw", $ARGV[0]) or die "open: $!";
      my $bytes = <$fh>;
      close $fh;
      my $text = eval { decode("UTF-8", $bytes, Encode::FB_CROAK) };
      if (!defined $text) { print "BADUTF8"; exit 0 }
      $text = NFKC($text);
      $text =~ s/\r//g; $text =~ s/[\x{200B}-\x{200D}\x{2060}\x{FEFF}\x{00AD}]//g;
      $text =~ s/\p{Zs}/ /g; $text =~ s/[\p{Pd}\x{2212}]/-/g; $text = lc($text);
      print(($text =~ /time[ \t\n-]*box/) ? "MENTIONS" : "CLEAN");' "$f") \
      || die "check-body could not normalise $f"
    case "$verdict" in
      CLEAN) ;;
      BADUTF8) die "check-body body is not valid UTF-8 — refusing to normalise" ;;
      MENTIONS)
        tr -d '\r' < "$f" | grep -qxE 'Follow-up: https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+' \
          || { echo "pass mentions a timebox but has no 'Follow-up: https://github.com/<owner>/<repo>/issues/<n>' line" >&2; exit 1; } ;;
      *) die "check-body got an unexpected verdict '$verdict'" ;;
    esac
    ;;
  *) die "unknown subcommand '$SUB'" ;;
esac
