#!/usr/bin/env bash
# Leak scan for this public fork. The identifier list is NOT in this repo: it comes from the
# LEAK_PATTERNS environment variable (a repo secret), one Perl regex per line.
#
# Usage:
#   leak-scan.sh commits <repo dir> <exclude-ref> <head> [<base>]
#       Scans every commit in <base>..<head> (or all of <head> when <base> is empty) that is not
#       reachable from <exclude-ref> (upstream main): added diff lines (diffed with --text, so
#       binary files are scanned too), added/renamed paths, commit message, author and committer
#       name and email. Merge commits: message plus --cc lines/paths. A diff git still reports as
#       binary is a hit (pattern=binary): its content was not scanned.
#   leak-scan.sh text <label>
#       Scans stdin, one record per line (used for PR title and body).
#
# Not scanned (outside this script's domain): tags and tag messages, branch names, PR and
# review comments, issue text, release notes. Only commits and what is piped into "text".
# A commit removed by a force-push before any run scanned it is never scanned, yet stays
# readable on GitHub by its SHA.
#
# Output never contains the matched text or the file path, only where it was:
#   HIT commit=<n> sha=<sha12> at=<kind>:<pos> pattern=<k>     (k = line number in LEAK_PATTERNS)
# Perl warnings are never printed (a regex warning quotes the pattern): a pattern that warns
# when compiled is reported as "pattern line <k> has a warning", any other warning as a count;
# both exit 2.
# Exit: 0 clean, 1 hit, 2 bad usage / git failure / patterns missing or warning (never read as clean).
#
# Optional env: LEAK_NOREPLY (the fork owner's noreply address) and LEAK_OWNER (the owner's
# account name). Nothing is removed from the text: every record (lines, paths, message, names,
# emails) is matched as is, then a hit is dropped only when it lies wholly inside one place
# where LEAK_OWNER or LEAK_NOREPLY appears (exact, case-sensitive match of the value). So a
# pattern equal to, or contained in, the owner name or noreply address does not hit there,
# but still hits anywhere else; a pattern that reaches past the owner text (for example
# owner/repo) hits. The same rule applies to the generic e-mail check.
# The committer email of a GitHub web merge (exactly GitHub's noreply address) is not an e-mail hit;
# that address in any other field (author, message, diff) still is.
# Limit: when a hit lies inside an owner span the match is retried one character later, never
# with a longer alternative from the same start. So a pattern that lists a shorter alternative
# equal to the owner first (owner|owner/secret), or uses a lazy quantifier, can miss owner/secret.
# A pattern that can match an empty string (a trailing "|", "a*") is refused when loaded; one
# that matches an empty string only in some text (a bare word boundary, a lookaround) is refused
# when that happens. Both exit 2 and name only the pattern line.
set -uo pipefail

SCANNER=''
IFS= read -r -d '' SCANNER <<'PERL' || true
use strict; use warnings;
my $WARNED = 0;                        # warning text can quote a pattern: count it, never print it
$SIG{__WARN__} = sub { $WARNED++ };
sub fin { my $rc = shift;
  if ($WARNED) { print STDERR "leak-scan: $WARNED perl warning(s), text suppressed\n"; $rc = 2; }
  exit $rc; }
my $mode = shift @ARGV;

if ($mode eq 'lines2rec') {            # arg: position prefix; stdin line -> "<prefix>:<n>\t<line>"
  my $p = shift @ARGV; my $n = 0;
  while (my $l = <STDIN>) { $n++; chomp $l; $l =~ s/\r\z//; print "$p:$n\t$l\n"; }
  fin(0);
}
if ($mode eq 'names2rec') {           # arg: prefix; stdin = NUL separated paths -> "<prefix>:path:<n>\t<path>"
  my $p = shift @ARGV; my $n = 0; local $/ = "\0";
  while (my $f = <STDIN>) { chomp $f; next if $f eq ''; $n++; $f =~ s/[\t\r\n]/ /g; print "$p:path:$n\t$f\n"; }
  fin(0);
}
if ($mode eq 'diff2rec') {             # args: prefix, column count (1, or parent count for merges)
  my ($p, $nc) = @ARGV; my ($fi, $ln, $hdr) = (0, 0, 0);
  my $all = '+' x $nc;
  while (my $l = <STDIN>) {
    chomp $l; $l =~ s/\r\z//;
    if ($l =~ /^diff /) { $hdr = 1; $fi++; next; }
    if ($hdr) {
      if ($l =~ /^(?:Binary files |GIT binary patch)/) { print "$p:diff:file$fi:binary\t\n"; next; }
      if ($l =~ /^(\@{2,}) -.*? \+(\d+)(?:,\d+)? \1/) { $hdr = 0; $ln = $2; }
      next;
    }
    if ($l =~ /^(\@{2,}) -.*? \+(\d+)(?:,\d+)? \1/) { $ln = $2; next; }
    next if $l =~ /^\\/;               # "\ No newline at end of file"
    my $pre = substr($l, 0, $nc);
    next if $pre =~ /-/;               # removed line (does not advance the new-file line number)
    if ($pre eq $all) { print "$p:diff:file$fi:line$ln\t", substr($l, $nc), "\n"; }
    $ln++;
  }
  fin(0);
}
die "unknown mode $mode\n" unless $mode eq 'records';

# Byte semantics on purpose (no decoding), same as the private pre-push scanner.
my (@pat, $k);
for my $p (split /\n/, ($ENV{LEAK_PATTERNS} // '')) {
  $k++; $p =~ s/\r\z//; next if $p eq '';
  my $w0 = $WARNED;
  my $re = eval { qr/$p/ };
  unless (defined $re) { print STDERR "leak-scan: pattern line $k does not compile\n"; exit 2; }
  if ($WARNED != $w0) { print STDERR "leak-scan: pattern line $k has a warning\n"; exit 2; }
  if ('' =~ $re) { print STDERR "leak-scan: pattern line $k can match an empty string\n"; exit 2; }
  push @pat, [$k, $re];
}
unless (@pat) { print STDERR "leak-scan: LEAK_PATTERNS is empty or unreadable\n"; exit 2; }
my $owner   = $ENV{LEAK_OWNER}   // '';
my $noreply = $ENV{LEAK_NOREPLY} // '';
my $EMAIL = qr/[A-Za-z0-9._%+-]+\@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+/a;
my $NR    = qr/\@users\.noreply\.github\.com\z/i;

my ($hits, $n) = (0, 0);
sub out { my ($pos, $what) = @_; my ($c, $s, $at) = split /:/, $pos, 3;
  if ($c =~ /^c(\d+)\z/) { print "HIT commit=$1 sha=$s at=$at pattern=$what\n"; }
  else { print "HIT at=$pos pattern=$what\n"; }
  $hits++; }
sub inside { my ($sp, $s, $e) = @_;    # hit [s, e) lies wholly within one owner span
  for (@$sp) { return 1 if $s >= $_->[0] && $e <= $_->[1]; } return 0; }
while (my $l = <STDIN>) {
  chomp $l; $l =~ s/\r\z//; $n++;
  my ($pos, $t) = split /\t/, $l, 2; $t //= '';
  if ($pos =~ /:binary\z/) { out($pos, 'binary'); next; }
  my $is_email = $pos =~ /:(?:author|committer)-email:/;
  # GitHub web merges are committed by GitHub's noreply address: only that field, only that value.
  # Written with \@ so this line itself does not look like an e-mail address to a scan.
  my $web_merge = $pos =~ /:committer-email:1\z/ && $t eq "noreply\@github.com";
  if ($is_email && $t !~ $NR && !$web_merge) { out($pos, 'non-noreply-email'); }
  my @own;                             # [start, end) of every owner / own-noreply occurrence
  for my $s (grep { $_ ne '' } $noreply, $owner) {
    my $q = quotemeta $s; while ($t =~ /$q/g) { push @own, [$-[0], $+[0]]; } }
  for my $pp (@pat) { my ($i, $re) = @$pp;
    while ($t =~ /$re/g) {
      # a zero-length match (\b, lookaround) would never move past an owner span at the end
      if ($-[0] == $+[0]) { print STDERR "leak-scan: pattern line $i matched an empty string\n"; exit 2; }
      if (inside(\@own, $-[0], $+[0])) { pos($t) = $-[0] + 1; next; }   # retry from the next char
      out($pos, $i); } }
  while ($t =~ /$EMAIL/g) { out($pos, 'email') unless $& =~ $NR || $web_merge || inside(\@own, $-[0], $+[0]); }
}
print STDERR "leak-scan: $n records, $hits hits\n";
fin($hits ? 1 : 0);
PERL
[ -n "$SCANNER" ] || { echo 'leak-scan: scanner failed to load' >&2; exit 2; }

die2(){ echo "leak-scan: $*" >&2; exit 2; }
usage(){ die2 "usage: leak-scan.sh commits <repo> <exclude-ref> <head> [<base>] | leak-scan.sh text <label>"; }
scan(){ perl -e "$SCANNER" -- records; local rc=$?
  case "$rc" in 0|1) return "$rc" ;; *) die2 "scanner failed (perl rc=${rc})" ;; esac; }

[ $# -ge 1 ] || usage
case "$1" in
  text)
    [ $# -eq 2 ] || usage
    perl -e "$SCANNER" -- lines2rec "$2" | scan; exit $? ;;
  commits) [ $# -eq 4 ] || [ $# -eq 5 ] || usage ;;
  *) usage ;;
esac

REPO="$2"; EXCL="$3"; HEADREF="$4"; BASE="${5:-}"
[ -d "$REPO" ] || die2 "not a directory"
G=(git -C "$REPO" -c core.quotePath=false -c color.ui=never -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.external=)
X=$("${G[@]}" rev-parse --verify --quiet "${EXCL}^{commit}") || die2 "cannot read exclude ref (no fallback to a full scan)"
H=$("${G[@]}" rev-parse --verify --quiet "${HEADREF}^{commit}") || die2 "cannot read head"
if [ -n "$BASE" ]; then
  B=$("${G[@]}" rev-parse --verify --quiet "${BASE}^{commit}") || die2 "cannot read base"
  COMMITS=$("${G[@]}" rev-list "$B..$H" --not "$X") || die2 "rev-list failed"
else
  COMMITS=$("${G[@]}" rev-list "$H" --not "$X") || die2 "rev-list failed"
fi

TMPD=$(mktemp -d) || die2 "mktemp failed"
trap 'command rm -rf "$TMPD"' EXIT
REC="$TMPD/records"; : > "$REC"
NC=0
for c in $COMMITS; do
  NC=$((NC+1)); s=$(printf '%.12s' "$c"); p="c${NC}:${s}"
  par=$("${G[@]}" rev-list --parents -n 1 "$c") || die2 "cannot read parents"
  set -- $par; np=$(( $# - 1 )); [ "$np" -ge 1 ] || np=1
  an=$("${G[@]}" log -1 --format=%an "$c") || die2 "cannot read author"
  ae=$("${G[@]}" log -1 --format=%ae "$c") || die2 "cannot read author"
  cn=$("${G[@]}" log -1 --format=%cn "$c") || die2 "cannot read committer"
  ce=$("${G[@]}" log -1 --format=%ce "$c") || die2 "cannot read committer"
  "${G[@]}" log -1 --format=%B "$c" > "$TMPD/msg" || die2 "cannot read message"
  # Diffs go to a file, not a variable: --text output can hold NUL bytes.
  if [ "$np" -ge 2 ]; then
    "${G[@]}" show --cc --text --format= --no-color --no-ext-diff --no-textconv "$c" > "$TMPD/diff" || die2 "git show --cc failed"
    "${G[@]}" diff-tree -r -z --name-only --no-commit-id --cc "$c" > "$TMPD/names" || die2 "diff-tree --cc failed"
  else
    "${G[@]}" show --text --format= --no-color --no-ext-diff --no-textconv -U0 "$c" > "$TMPD/diff" || die2 "git show failed"
    "${G[@]}" diff-tree -r -z --name-only --no-commit-id --root -M --diff-filter=AR "$c" > "$TMPD/names" || die2 "diff-tree failed"
  fi
  printf '%s:author-name:1\t%s\n%s:author-email:1\t%s\n%s:committer-name:1\t%s\n%s:committer-email:1\t%s\n' \
    "$p" "$an" "$p" "$ae" "$p" "$cn" "$p" "$ce" >> "$REC" || die2 "write failed"
  perl -e "$SCANNER" -- lines2rec "${p}:msg" < "$TMPD/msg" >> "$REC" || die2 "message records failed"
  perl -e "$SCANNER" -- diff2rec "$p" "$np" < "$TMPD/diff" >> "$REC" || die2 "diff records failed"
  perl -e "$SCANNER" -- names2rec "$p" < "$TMPD/names" >> "$REC" || die2 "path records failed"
done
echo "leak-scan: ${NC} commits after excluding upstream" >&2
scan < "$REC"; exit $?
