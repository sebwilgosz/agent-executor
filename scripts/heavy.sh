#!/usr/bin/env bash
# heavy.sh — a machine-wide slot for one heavy command. No AI.
# Many sessions at once starve the CPU, so heavy commands take turns. The call
# blocks until it holds a slot or the wait limit passes. CONTRIBUTING's rule 5 asks
# for non-blocking where it can be; waiting is what this script is for.
#
# Usage:   heavy.sh <shell pid> <label>
#          bash heavy.sh $$ npm-test; npm test
#
# A slot is a kernel lock on a file in the state folder, kept by a detached holder
# that watches the shell. When the holder dies, for any reason, the kernel frees the
# slot, so there is nothing stale to clean up. A lock also can't go stale the way a
# PID file does, on a machine where PIDs wrap in minutes.
#
# State folder: ~/.engineer-of-wealth/executor (EXECUTOR_HEAVY_DIR overrides it).
#   heavy.json   the settings; no file means the queue is off. Optional keys:
#                slots (2), wait_minutes (20), hold_minutes (30)
#   heavy.log    one line per outcome, never the command text, which can hold secrets:
#                <time>  <label>  <cwd>  waited=<s>  acquired|wait-expired|hold-expired|failed
#                <time>  <label>  <cwd>  waited=<s>  released  held=<s>
#   slot-<n>.lock  the locks, and the label and cwd of their holders
#
# Always fails open: any failure returns promptly and the command runs without a
# slot. Nothing is ever killed. The exit code is always 0. Stdout stays empty, and
# stderr has only the one line that says what the call is waiting for.
set -u

DIR="${EXECUTOR_HEAVY_DIR:-${HOME:-}/.engineer-of-wealth/executor}"
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
[ -e "$DIR/heavy.json" ] || exit 0

LABEL="${2:-unknown}"

if ! command -v perl >/dev/null 2>&1 \
  || ! perl -x "$0" "$DIR" "${1:-}" "$LABEL" "$PWD" </dev/null >/dev/null 3>&2 2>/dev/null; then
  { printf '%s  %s  %s  waited=0  failed\n' "$(date '+%F %T')" "${LABEL//[[:cntrl:]]/ }" "${PWD//[[:cntrl:]]/ }" >> "$DIR/heavy.log"; } 2>/dev/null
fi
exit 0

#!perl
use strict;
use warnings;
use B ();
use Fcntl qw(:flock O_RDWR O_CREAT);
use POSIX ();
use Time::HiRes qw(time sleep);

my ($dir, $pid, $label, $cwd) = @ARGV;
s/[[:cntrl:]]/ /g for $label, $cwd;
$SIG{PIPE} = 'IGNORE';

my $start = time;
my $acquired;

sub note {
    my ($outcome, $extra) = @_;
    my $waited = int(($acquired // time) - $start);
    my $line = join '  ', POSIX::strftime('%F %T', localtime), $label, $cwd,
        "waited=$waited", $outcome, $extra // ();
    open my $log, '>>', "$dir/heavy.log" or return;
    syswrite $log, "$line\n";
}

sub fail { note('failed'); exit 0 }

# EPERM still means the process exists.
sub alive { kill(0, $pid) || $!{EPERM} }

# An exited shell whose parent hasn't reaped it still answers kill 0.
sub zombie {
    open my $ps, '-|', 'ps', '-o', 'stat=', '-p', $pid or return 0;
    my $stat = <$ps> // '';
    close $ps;
    $stat =~ /^\s*Z/;
}

sub positive {
    my ($v) = @_;
    return 0 if !defined $v || ref $v;
    my $flags = B::svref_2object(\$v)->FLAGS;
    return 0 if $flags & B::SVf_POK || !($flags & (B::SVf_IOK | B::SVf_NOK));
    $v > 0 && $v < 9**9**9;
}

sub settings {
    require JSON::PP;
    open my $fh, '<', "$dir/heavy.json" or die;
    my $json = JSON::PP->new->decode(do { local $/; <$fh> // '' });
    die unless ref $json eq 'HASH';
    my %set = (slots => 2, wait_minutes => 20, hold_minutes => 30);
    for my $key (keys %set) {
        next unless exists $json->{$key};
        die unless positive($json->{$key});
        $set{$key} = $json->{$key};
    }
    die unless $set{slots} == int $set{slots};
    @set{qw(slots wait_minutes hold_minutes)};
}

# What holds a slot, by probing with a shared lock, so that probes never get in
# each other's way. A slot number above a lowered count still counts.
sub holders {
    my ($except) = @_;
    my @who;
    opendir my $d, $dir or return @who;
    for my $name (grep { /^slot-\d+\.lock$/ } readdir $d) {
        next if defined $except && $name eq $except;
        open my $fh, '<', "$dir/$name" or next;
        next if flock $fh, LOCK_SH | LOCK_NB;
        my $who = <$fh> // '';
        chomp $who;
        push @who, $who;
    }
    @who;
}

sub take {
    my ($slots) = @_;
    for my $n (1 .. $slots) {
        my $name = "slot-$n.lock";
        sysopen my $fh, "$dir/$name", O_RDWR | O_CREAT, 0600 or die;
        unless (flock $fh, LOCK_EX | LOCK_NB) {
            die unless $!{EWOULDBLOCK};
            next;
        }
        return undef if 1 + holders($name) > $slots;
        truncate $fh, 0;
        syswrite $fh, "$label in $cwd\n";
        return $fh;
    }
    undef;
}

# The lock lives on in this process: a forked copy shares it, and the kernel frees
# it once the last copy closes. So no explicit unlock, here or in the parent.
sub keep_slot {
    my ($slot, $hold) = @_;
    POSIX::setsid();
    chdir '/';
    open STDIN,  '<', '/dev/null' or close STDIN;
    open STDOUT, '>', '/dev/null' or close STDOUT;
    open STDERR, '>', '/dev/null' or close STDERR;
    POSIX::close($_) for grep { $_ != fileno $slot } 3 .. 1023;

    my $tick = 0;
    while (1) {
        sleep 1;
        if (!alive() || (++$tick % 3 == 0 && zombie())) {
            note('released', 'held=' . int(time - $acquired));
            exit 0;
        }
        if (time - $acquired >= $hold * 60) {
            note('hold-expired');
            exit 0;
        }
    }
}

fail() unless $pid =~ /^[1-9][0-9]*$/ && alive();

my ($slots, $wait, $hold) = eval { settings() };
fail() unless defined $slots;

{
    open my $log, '>>', "$dir/heavy.log" or exit 0;
}

setpriority(0, $pid, (getpriority(0, $pid) // 0) + 10);

my ($polls, $told) = (0, 0);
while (1) {
    my $slot = eval { take($slots) };
    fail() if $@;
    if ($slot) {
        $acquired = time;
        my $child = fork;
        fail() unless defined $child;
        keep_slot($slot, $hold) unless $child;
        note('acquired');
        exit 0;
    }
    fail() unless alive();
    if (time - $start >= $wait * 60) {
        note('wait-expired');
        exit 0;
    }
    # One miss can be another call's check of the same lock, not a real wait.
    if (!$told && ++$polls >= 2) {
        my @who = grep { length } holders();
        if (@who && open my $err, '>&=', 3) {
            $err->autoflush(1);
            print $err 'heavy.sh: waiting for a slot held by ' . join('; ', @who) . "\n";
            $told = 1;
        }
    }
    sleep 0.5;
}
