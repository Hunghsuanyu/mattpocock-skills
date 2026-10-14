#!/usr/bin/env bash
# Tests for .github/scripts/leak-scan.sh and the push branch of .github/workflows/leak-scan.yml.
# Everything runs on throwaway git repos built here, with harmless made-up patterns
# (ZZCANARYZZ, Acme{Corp, OwnerQQ). No network, no gh, no secrets.
#
# Every failing case is paired with a known-hit control, so "0 hits" is never read as clean
# by a scan that simply saw nothing.
#
# Usage:
#   test-leak-scan.sh                 run the tests (exit 0 = all passed)
#   test-leak-scan.sh --mutations     apply each mutation below to a copy and expect the tests
#                                     to fail (exit 0 = every mutation was caught). Not run by CI.
# Overrides (set by --mutations): LEAK_SCAN=<leak-scan.sh copy>  LEAK_WF=<leak-scan.yml copy>
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
SCAN=${LEAK_SCAN:-$ROOT/.github/scripts/leak-scan.sh}
WF=${LEAK_WF:-$ROOT/.github/workflows/leak-scan.yml}
REAL_GIT=$(command -v git)
T=$(mktemp -d) || exit 2
trap 'command rm -rf "$T"' EXIT

# Mutations: <name> TAB <sed -E expression> TAB <scan|wf>. Each must turn the tests red.
MUTATIONS='warn-handler	s/^\$SIG\{__WARN__\} = .*$//	scan
binary-hit	s/\(\?:Binary files \|GIT binary patch\)/(?:QQNEVERQQ)/	scan
author-name	s/"\$p" "\$an"/"$p" ""/	scan
owner-strip-all	s/if \$is_email \&\& \$owner ne/if $owner ne/	scan
push-before	s/head="\$AFTER"; base=""/head="$AFTER"; base="$BEFORE"/	wf'

if [ "${1:-}" = --mutations ]; then
  caught=0; missed=0; TAB=$(printf '\t')
  while IFS="$TAB" read -r name expr target; do
    cp "$SCAN" "$T/scan.sh"; cp "$WF" "$T/wf.yml"
    f="$T/scan.sh"; [ "$target" = wf ] && f="$T/wf.yml"
    sed -E "$expr" "$f" > "$T/mut" || { echo "mutation $name: sed failed"; exit 2; }
    if cmp -s "$f" "$T/mut"; then echo "mutation $name: did not apply"; exit 2; fi
    cp "$T/mut" "$f"
    LEAK_SCAN="$T/scan.sh" LEAK_WF="$T/wf.yml" bash "$0" > "$T/mut.out" 2>&1; rc=$?
    if [ "$rc" -ne 0 ]; then caught=$((caught+1)); echo "caught - $name"; grep '^not ok' "$T/mut.out" | sed 's/^/    /' 
    else missed=$((missed+1)); echo "MISSED - $name"; fi
  done <<EOF
$MUTATIONS
EOF
  echo "# mutations: $caught caught, $missed missed"
  [ "$missed" -eq 0 ]; exit $?
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok - $1"; }
bad() { FAIL=$((FAIL+1)); echo "not ok - $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; echo "  --- output (rc=$RC):"; sed 's/^/  | /' "$OUT"; fi; }
has()   { grep -qF -- "$1" "$OUT"; }
lacks() { ! grep -qF -- "$1" "$OUT"; }
N=0
# run <cmd...>: stdout+stderr into a fresh $OUT, exit code into $RC.
run() { N=$((N+1)); OUT="$T/out.$N"; "$@" > "$OUT" 2>&1; RC=$?; }

# ---------- synthetic repo ----------
R="$T/repo"
mkdir -p "$R"
g() { "$REAL_GIT" -C "$R" "$@"; }
g init -q
g config user.name 'Plain Name'
g config user.email 'plain@users.noreply.github.com'
g config commit.gpgsign false
echo base > "$R/README"; g add README; g commit -qm base
U=$(g rev-parse HEAD)                                   # stands in for upstream main
printf '%s\n' "$U" > "$R/.git/FETCH_HEAD"

echo 'line ZZCANARYZZ here' > "$R/a.txt"; g add a.txt; g commit -qm 'add a'
A=$(g rev-parse HEAD)
echo 'clean' > "$R/b.txt"; g add b.txt; g commit -qm 'add b'
B=$(g rev-parse HEAD)

# ---------- 1. pattern warnings never print the pattern ----------
P_WARN='Acme{Corp'                                       # "Unescaped left brace" warning quotes the regex
run env LEAK_PATTERNS="$P_WARN" bash "$SCAN" text t <<< 'hello Acme{Corp'
check 'text: warning pattern => rc 2' '[ "$RC" -eq 2 ]'
check 'text: warning pattern text not in output' 'lacks Acme && lacks Corp'
check 'text: warning names the pattern line only' 'has "pattern line 1 has a warning"'

run env LEAK_PATTERNS="$(printf 'ZZCANARYZZ\n%s' "$P_WARN")" bash "$SCAN" text t <<< 'x'
check 'text: second-line warning pattern => rc 2, line 2 named' '[ "$RC" -eq 2 ] && has "pattern line 2 has a warning" && lacks Acme'

run env LEAK_PATTERNS="$P_WARN" bash "$SCAN" commits "$R" "$U" "$B"
check 'commits: warning pattern => rc 2, text not in output' '[ "$RC" -eq 2 ] && lacks Acme && lacks Corp'

run env LEAK_PATTERNS='ZZCANARYZZ' bash "$SCAN" text t <<< 'xZZCANARYZZx'
check 'control: clean pattern hits => rc 1, pattern=1, text not in output' '[ "$RC" -eq 1 ] && has "pattern=1" && lacks ZZCANARYZZ'

# ---------- 2. push twice, first run cancelled: the second still scans the first commit ----------
# Pull the real "Scan commits" run block out of the workflow and execute it as the runner would.
awk '
  /- name: Scan commits/ { f=1; next }
  f && /^        run: \|/ { r=1; next }
  r && /^      - / { exit }
  r { sub(/^          /, ""); print }
' "$WF" > "$T/push-step.sh"
mkdir -p "$R/.github/scripts"; cp "$SCAN" "$R/.github/scripts/leak-scan.sh"   # untracked: never scanned
push_run() { ( cd "$R" && env LEAK_PATTERNS=ZZCANARYZZ EVENT=push BEFORE="$1" AFTER="$2" \
  PR_BASE= PR_HEAD= bash "$T/push-step.sh" ); }
check 'workflow push block extracted' '[ -s "$T/push-step.sh" ]'
run push_run "$U" "$A"
check 'control: push 1 (before=upstream, after=A) hits A' '[ "$RC" -eq 1 ] && has "sha=${A:0:12}"'
run push_run "$A" "$B"
check 'push 2 (before=A, after=B) still hits A' '[ "$RC" -eq 1 ] && has "sha=${A:0:12}" && lacks ZZCANARYZZ'
run env LEAK_PATTERNS=ZZCANARYZZ bash "$SCAN" commits "$R" "$U" "$B" "$A"
check 'control: a before..after range alone misses A (case discriminates)' '[ "$RC" -eq 0 ]'

# ---------- 3. author / committer names ----------
g checkout -q -b names "$U"
echo n > "$R/n.txt"; g add n.txt
GIT_AUTHOR_NAME='Ann ZZCANARYZZ' GIT_COMMITTER_NAME='Cid ZZCANARYZZ' g commit -qm 'names'
NM=$(g rev-parse HEAD)
run env LEAK_PATTERNS=ZZCANARYZZ bash "$SCAN" commits "$R" "$U" "$NM"
check 'author name scanned' '[ "$RC" -eq 1 ] && has "at=author-name:1 pattern=1"'
check 'committer name scanned' 'has "at=committer-name:1 pattern=1" && lacks ZZCANARYZZ'

# ---------- 4. binary files ----------
g checkout -q -b bin "$U"
printf '*.bin binary\n' > "$R/.gitattributes"; printf 'a\000bZZCANARYZZ\n' > "$R/f.bin"
g add .gitattributes f.bin; g commit -qm 'bin'
BN=$(g rev-parse HEAD)
run env LEAK_PATTERNS=ZZCANARYZZ bash "$SCAN" commits "$R" "$U" "$BN"
check 'binary-attributed file content scanned as text' '[ "$RC" -eq 1 ] && has "at=diff:file2:line1 pattern=1" && lacks ZZCANARYZZ'
# Simulate git still reporting "Binary files ... differ" (a git that ignores --text).
mkdir -p "$T/shim"
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
a=(); for x in "\$@"; do [ "\$x" = --text ] || a+=("\$x"); done
exec "$REAL_GIT" \${a[@]+"\${a[@]}"}
EOF
chmod +x "$T/shim/git"
run env PATH="$T/shim:$PATH" LEAK_PATTERNS=QQNOMATCHQQ bash "$SCAN" commits "$R" "$U" "$BN"
check 'still-binary diff => HIT pattern=binary' '[ "$RC" -eq 1 ] && has "pattern=binary"'

# ---------- 5. LEAK_OWNER is removed from email fields only ----------
g checkout -q -b owner "$U"
echo o > "$R/o.txt"; g add o.txt
GIT_AUTHOR_EMAIL='1+OwnerQQ@users.noreply.github.com' GIT_COMMITTER_EMAIL='1+OwnerQQ@users.noreply.github.com' \
  g commit -qm 'see the OwnerQQ page'
OW=$(g rev-parse HEAD)
run env LEAK_PATTERNS=OwnerQQ LEAK_OWNER=OwnerQQ LEAK_NOREPLY='1+OwnerQQ@users.noreply.github.com' \
  bash "$SCAN" commits "$R" "$U" "$OW"
check 'owner in message still hits' '[ "$RC" -eq 1 ] && has "at=msg:1 pattern=1"'
check 'owner in own noreply email does not hit' 'lacks "author-email" && lacks "committer-email" && lacks OwnerQQ'

# ---------- 6. no output anywhere carried a test string ----------
if grep -lE 'ZZCANARYZZ|Acme|OwnerQQ' "$T"/out.* > "$T/leaky"; then
  bad "no output contains a pattern string ($(wc -l < "$T/leaky" | tr -d ' ') files)"
else
  ok 'no output contains a pattern string'
fi

echo "# leak-scan: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
