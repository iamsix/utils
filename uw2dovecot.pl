#!/usr/bin/perl -w

use strict;
use Getopt::Std;
use Time::Local;
use File::Find;
use File::Path;
use File::Basename;

my %opts;
my $inbox;
my $uwmaildir;
my $subscriptions;
my $maildir;
my $separator;
my $replacement;
my @inbox_stat;
my @maildir_stat;
my $hostname;
my $totalmsgs = 0;
my %months = (
	'Jan' => 0,
	'Feb' => 1,
	'Mar' => 2,
	'Apr' => 3,
	'May' => 4,
	'Jun' => 5,
	'Jul' => 6,
	'Aug' => 7,
	'Sep' => 8,
	'Oct' => 9,
	'Nov' => 10,
	'Dec' => 11
);

# mix format:
#	.mixmeta:
#		V UIDVALIDITY(hex)
#		K key0 key1 key2
#	.mixindex:
#		:uid:yyyymmddhhmmss[-+]zzzz:rfcsize:fileid:offset:mixhdrsz:hdrsz:
#	.mixstatus:
#		:uid:keywordflags:sysflags:modval:
#		keywordflags from .mixmeta
#		sysflags:
#			0x01 = SEEN
#			0x02 = TRASH
#			0x04 = FLAG
#			0x08 = REPLIED
#			0x10 = OLD (cur, else new)
#			0x20 = DRAFT (not used)
#
# mbx format:
#	all data has \r\n
#	*mbx*
#	VVVVVVVVUUUUUUUU (V=VALIDITY, U=NEXT UID but often lazy assignment)
#	key0
#	key1
#	...
#	key29
#	pad to 2048 bytes, last 10 bytes can be LASTPID\r\n
#	DD-MMM-YYYY HH:MM:SS [+-]ZZZZ,length(dec);kkkkkkkkssss-uuuuuuuu
#	msg
#	...
#
# mbox format:
#	From_ lines at begining of each message
#	can have:
#	X-IMAP: UIDVALIDITY MEXTUID (often lazy assignment)
#	X-IMAPbase: UIDVALIDITY NEXTUID (lazy and indicates pseudo message)
#	Status: FLAGS
#	X-Status: FLAGS
#	X-Keywords: key ...
#
# .mailboxlist:
#	folder (strip mail/, convert / to separator)
#	...
#
# dovecot-keywords:
#	number(dec) keyword
#	...
# dovecot-uidlist:
#	1 UIDVALIDITY(dec) NEXT
#	uid(dec) filename
# subscriptions
#	folder
#	...
# cur
#	timestamp.uid.hostname:2,flags
#	flags = F(lag), R(eplied), S(een), T(rash), a-z (keywords)
# new
#	timestamp.uid.hostname
# .sub.folder:
#	maildirfolder (exists to make dovecot happy)
#	dovecot-keywords (as above)
#	dovecot-uidlist (as above)

sub convert($$$) {
	my $mailbox = shift(@_);
	my $outdir = shift(@_);
	my $subfolder = shift(@_);
	my $uidvalidity;
	my @keywords;
	my $line;
	my %msgs;
	if (-d $mailbox) {
		eval {
			open(META, '<', "$mailbox/.mixmeta") || die "Can't open $mailbox/.mixmeta";
			open(INDEX, '<', "$mailbox/.mixindex") || die "Can't open $mailbox/.mixindex";
			open(STATUS, '<', "$mailbox/.mixstatus") || die "Can't open $mailbox/.mixstatus";
		};
		if ($@) {
			warn $@;
			return;
		}
		while ($line = <META>) {
			if ($line =~ m/^V([[:xdigit:]]{8})\r\n$/) {
				$uidvalidity = hex($1);
			} elsif ($line =~ m/^K(.*)\r\n$/) {
				@keywords = split(' ', $1);
			}
		}
		close(META);
		if (!defined($uidvalidity)) {
			warn "$mailbox: No uidvalidity";
			return;
		}
		while ($line = <INDEX>) {
			my $tmpvals;
			my $hdr;
			if ($line =~ m/^:([[:xdigit:]]{8}):(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)([-+])(\d\d)(\d\d):([[:xdigit:]]{8}):([[:xdigit:]]{8}):([[:xdigit:]]{8}):([[:xdigit:]]{8}):([[:xdigit:]]{8}):\r\n$/) {
				my $uidl = $1;
				$tmpvals = {
					'timestamp' => timegm($7, $6, $5, $4, $3-1, $2) + (($8 eq '-' ? 1 : -1)*($9 * 60 + $10)*60),
					'size' => hex($11),
					'filename' => "$mailbox/.mix$12",
					'offset' => hex($13),
					'skip' => hex($14),
				};
				eval {
					open(MSGFILE, '<', $tmpvals->{'filename'}) || die "Can't open ".$tmpvals->{'filename'};
					seek(MSGFILE, $tmpvals->{'offset'}, 0) || die "Can't seek to ".$tmpvals->{'offset'};
					read(MSGFILE, $hdr, $tmpvals->{'skip'}) || die "Can't read ".$tmpvals->{'skip'}."bytes from ".$tmpvals->{'filename'};
					($hdr eq ":msg:$1:$2$3$4$5$6$7$8$9$10:$11:\r\n") || die "Header/index mismatch for $uidl in ".$tmpvals->{'filename'};
					close(MSGFILE);
				};
				if ($@) {
					warn "Skipping message: $@";
					next;
				}
				$msgs{$uidl} = $tmpvals;
			}
		}
		close(INDEX);
		while ($line = <STATUS>) {
			if ($line =~ m/^:([[:xdigit:]]{8}):([[:xdigit:]]{8}):([[:xdigit:]]{4}):([[:xdigit:]]{8}):\r\n$/) {
				if (!defined($msgs{$1})) {
					# .mixstatus file can have entries for deleted messages
					next;
				}
				$msgs{$1}{'new'} = !(hex($3) & 0x10);
				$msgs{$1}{'flags'} =
					((hex($3) & 0x1) ? 'S' : '').
					((hex($3) & 0x2) ? 'T' : '').
					((hex($3) & 0x4) ? 'F' : '').
					((hex($3) & 0x8) ? 'R' : '');
				foreach my $i (0 .. 25) {
					if (hex($2) & (1 << $i)) {
						$msgs{$1}{'flags'} .= chr(ord('a') + $i);
					}
				}
			}
		}
		close(STATUS);
		$totalmsgs += scalar(keys(%msgs));
		print "$mailbox: Converting mix file (".scalar(keys(%msgs))." messages)\n" if $opts{'v'};
	} else {
		close(MAILBOX); #force $. reset
		open(MAILBOX, '<', $mailbox);
		$line = <MAILBOX>;
		if (!defined($line)) {
			print "$mailbox: Empty file (0 messages)\n" if $opts{'v'};
		} elsif ($line eq "*mbx*\r\n") {
			$line = <MAILBOX>;
			if ($line =~ /^([[:xdigit:]]{8})([[:xdigit:]]{8})\r\n$/) {
				$uidvalidity = hex($1);
			} else {
				warn "$mailbox: Bogus UID line";
				return;
			}
			foreach my $n (0 .. 29) {
				$line = <MAILBOX>;
				$line =~ s/\r\n//;
				if ($line ne '') {
					push(@keywords, $line);
				}
			}
			seek(MAILBOX, 2048, 0);
			my $lazyuid = 0;
			while ($line = <MAILBOX>) {
				if ($line =~ m/( \d|\d\d)-(\w\w\w)-(\d\d\d\d) (\d\d):(\d\d):(\d\d) ([+-])(\d\d)(\d\d),(\d+);([[:xdigit:]]{8})([[:xdigit:]]{4})-([[:xdigit:]]{8})\r\n$/) {
					if ($13 eq '00000000') {
						$lazyuid++;
					} else {
						$lazyuid = hex($13);
					}
					my $hexuid = sprintf('%08x', $lazyuid);
					$msgs{$hexuid} = {
						'timestamp' => timegm($6, $5, $4, $1+0, $months{$2}, $3) + (($8 eq '-' ? 1 : -1)*($8 * 60 + $9)*60),
						'size' => $10,
						'filename' => $mailbox,
						'offset' => tell(MAILBOX),
						'skip' => 0,
						'new' => !(hex($12) & 0x10),
						'flags' =>
							((hex($12) & 0x1) ? 'S' : '').
							((hex($12) & 0x2) ? 'T' : '').
							((hex($12) & 0x4) ? 'F' : '').
							((hex($12) & 0x8) ? 'R' : ''),
					};
					foreach my $i (0 .. 25) {
						if (hex($11) & (1 << $i)) {
							$msgs{$hexuid}{'flags'} .= chr(ord('a') + $i);
						}
					}
					seek(MAILBOX, $msgs{$hexuid}{'size'}, 1);
				} else {
					warn "Bogus line in mbx";
				}
			}
			$totalmsgs += scalar(keys(%msgs));
			print "$mailbox: Converting mbx file (".scalar(keys(%msgs))." messages)\n" if $opts{'v'};
		} elsif ($line =~ m/^From /) {
			seek(MAILBOX, 0, 0);
			my $lazyuid = 0;
			my $tmpoffset;
			my $tmptimestamp;
			my %tmpkeywords = ();
			my $tmpflags;
			my $tmpnew;
			my $pseudomsg;
			my $end = 0;
			my $inheader = 0;
			$uidvalidity = time();
			while ($line = <MAILBOX>) {
				if ($line =~ m/^From (?:\S+)\s+... ... (?: \d|\d\d) \d\d:\d\d:\d\d \d\d\d\d(?: [+-]\d\d\d\d)?\n$/) {
					if ($end > 0 && !$pseudomsg) {
						# found end of current message, capture info
						my $hexuid = sprintf('%08x', $lazyuid);
						$msgs{$hexuid} = {
							'timestamp' => $tmptimestamp,
							'size' => $end - $tmpoffset,
							'filename' => $mailbox,
							'offset' => $tmpoffset,
							'skip' => 0,
							'new' => $tmpnew,
							'flags' => $tmpflags
						};
					}
					# capture $n vars here, just to avoid confusion, but to confuse, (?:) is grouping without capturing
					$line =~ m/^From (?:\S+)\s+... (...) ( \d|\d\d) (\d\d):(\d\d):(\d\d) (\d\d\d\d)(?: ([+-])(\d\d)(\d\d))?\n$/;
					$tmpoffset = tell(MAILBOX);
					$inheader = 1;
					$tmptimestamp = timegm($5, $4, $3, $2+0, $months{$1}, $6) + (defined($8) ? (($7 eq '-' ? 1 : -1)*($8 * 60 + $9)*60) : 0);
					$tmpflags = '';
					$tmpnew = 1;
					$lazyuid++;
					$pseudomsg = 0;
				} elsif ($inheader) {
					if ($line =~ m/X-IMAP(base)?: (\d+) (\d+)\n$/) {
						$uidvalidity = $2;
						# X-IMAP: means pseudo message
						if (!defined($1)) {
							$pseudomsg = 1;
							$lazyuid = 0;
						}
					} elsif ($line =~ m/X-Keywords:\s+(.*)\n$/) {
						foreach my $kw (split(' ', $1)) {
							if (!defined($tmpkeywords{$kw})) {
								$tmpkeywords{$kw} = scalar(@keywords);
								push(@keywords, $kw);
							}
							if ($tmpkeywords{$kw} < 26) {
								$tmpflags .= chr(ord('a') + $tmpkeywords{$kw});
							}
						}
					} elsif ($line =~ m/X-UID: (\d+)\n$/) {
						$lazyuid = $1;
					} elsif ($line =~ m/^(X-)?Status: (\S+)/) {
						foreach my $f (split(//, $2)) {
							if ($f eq 'R') {
								$tmpflags .= 'S';
							} elsif ($f eq 'A') {
								$tmpflags .= 'R';
							} elsif ($f eq 'F') {
								$tmpflags .= 'F';
							} elsif ($f eq 'D') {
								$tmpflags .= 'T';
							} elsif ($f eq 'O') {
								$tmpnew = 0;
							}
						}
					} elsif ($line =~ m/^\n$/) {
						$inheader = 0;
						$end = tell(MAILBOX);
					}
				} else {
					$end = tell(MAILBOX);
				}
			}
			# catch last message (if one)
			if ($end > 0 && !$pseudomsg) {
				# found end of current message, capture info
				my $hexuid = sprintf('%08x', $lazyuid);
				$msgs{$hexuid} = {
					'timestamp' => $tmptimestamp,
					'size' => $end - $tmpoffset,
					'filename' => $mailbox,
					'offset' => $tmpoffset,
					'skip' => 0,
					'new' => $tmpnew,
					'flags' => $tmpflags
				};
			}
			$totalmsgs += scalar(keys(%msgs));
			print "$mailbox: Converting mbox file (".scalar(keys(%msgs))." messages)\n" if $opts{'v'};
		} else {
			print "$mailbox: Unknown file format, skipping\n" if $opts{'v'};
			return;
		}
	}
	eval {
		mkpath($outdir);
	};
	if ($@) {
		warn $@;
		return;
	}
	if (scalar(@keywords) > 26) {
		warn "$mailbox: Too many keywords, only first 26 will be kept";
		@keywords=@keywords[0 .. 25];
	}
	if (scalar(@keywords) > 0) {
		open(KEYWORDS, '>', "$outdir/dovecot-keywords");
		foreach my $kn (0 .. $#keywords) {
			print KEYWORDS "$kn ${keywords[$kn]}\n";
		}
		close(KEYWORDS);
	}
	mkdir("$outdir/tmp");
	mkdir("$outdir/new");
	mkdir("$outdir/cur");
	if ($subfolder) {
		open(SUBFOLDER, '>', "$outdir/maildirfolder");
		close(SUBFOLDER);
	}
	if (scalar(keys(%msgs))) {
		my $maxuidl = 0;
		foreach my $uidl (sort(keys(%msgs))) {
			if (hex($uidl) > $maxuidl) {
				$maxuidl = hex($uidl);
			}
		}
		open(UIDLIST, '>', "$outdir/dovecot-uidlist");
		print UIDLIST "1 $uidvalidity ".($maxuidl + 1)."\n";
		foreach my $uidl (sort(keys(%msgs))) {
			my $msg = $msgs{$uidl};
			my $data;
			eval {
				open(MSG, '<', $msg->{'filename'}) || die "Can't open ".$msg->{'filename'};
				seek(MSG, $msg->{'offset'}+$msg->{'skip'}, 0) || die "Can't seek to ".($msg->{'offset'}+$msg->{'skip'});
				read(MSG, $data, $msg->{'size'}) || die "Can't read ".$msg->{'size'}." bytes from ".$msg->{'filename'};
				close(MSG);
			};
			if ($@) {
				warn $@;
				next;
			}
			$data =~ s/\r\n/\n/g;
			my $filebase = $msg->{'timestamp'}.'.'.$uidl.'.'.$hostname;
			if (!$msg->{'new'}) {
				$filebase .= ':2,'.$msg->{'flags'};
			}
			my $filename = $outdir.'/'.($msg->{'new'} ? 'new' : 'cur').'/'.$filebase;
			print UIDLIST hex($uidl)." $filebase\n";
			open(NEWFILE, '>', $filename);
			print NEWFILE $data;
			close(NEWFILE);
			utime($msg->{'timestamp'}, $msg->{'timestamp'}, $filename);
		}
		close(UIDLIST);
	}
}

sub findfunc() {
	my @s = stat($_);
	# check for maildir and prune
	if ($s[1] == $maildir_stat[1] && $s[0] == $maildir_stat[0]) {
		$File::Find::prune = 1;
		return;
	}
	# skip inbox
	if ($s[1] == $inbox_stat[1] && $s[0] == $inbox_stat[0]) {
		return;
	}
	if (basename($_) =~ m/^\.mix/) {
		return;
	}
	if (-d $_ && ! -e $_.'/.mixstatus') {
		return;
	}
	my $tmpnam = $File::Find::name;
	$tmpnam =~ s/^\Q$uwmaildir\E\///;
	if ($separator eq '/') {
		convert($File::Find::name, $maildir.'/'.$tmpnam, 1);
	} else {
		$tmpnam =~ s/\Q$separator/$replacement/g;
		$tmpnam =~ s/\//$separator/g;
		convert($File::Find::name, $maildir.'/'.$separator.$tmpnam, 1);
	}
}

#
# main body
#

getopts('hi:u:s:m:p:r:v', \%opts);
if (defined($opts{'h'})) {
	print "Usage:\n";
	print "\t-h (help)\n";
	print "\t-i inbox [INBOX]\n";
	print "\t-u uwmaildir [mail] ('' to skip)\n";
	print "\t-s subscriptions [.mailboxlist] ('' to skip)\n";
	print "\t-m maildir [Maildir]\n";
	print "\t-p path-separator [.] (use / if using LAYOUT=fs, anything else may not work as expected)\n";
	print "\t-r replacement [_] (replacement for path-separator, for listescape plugin, make sure to quote \\ properly)\n";
	print "\t-v (verbose)\n";
	print "\n";
	print "maildir must not exist\n";
	print "assumes that job is being run as user owning all files\n";
	print "conversion is completely non-destructive, all original files are left intact\n";
	exit 0;
}
$inbox = defined($opts{'i'}) ? $opts{'i'} : 'INBOX';
$uwmaildir = defined($opts{'u'}) ? $opts{'u'} : 'mail';
$subscriptions = defined($opts{'s'}) ? $opts{'s'} : '.mailboxlist';
$maildir = defined($opts{'m'}) ? $opts{'m'} : 'Maildir';
$separator = defined($opts{'p'}) ? $opts{'p'} : '.';
$replacement = defined($opts{'r'}) ? $opts{'r'} : '_';
chomp($hostname = `hostname`);

die "$maildir must not exist" if (-e $maildir);
die "$inbox doesn't exist" if (! -e $inbox);
die "$uwmaildir doesn't exist" if ($uwmaildir ne '' && ! -d $uwmaildir);
die "$subscriptions doesn't exist" if ($subscriptions ne '' && ! -e $subscriptions);

umask(077);

convert($inbox, $maildir, 0);

# get dev/ino info for inbox and maildir so if we happen to be converting . we don't convert them as well
@inbox_stat = stat($inbox);
@maildir_stat = stat($maildir);

#if (-d $inbox) {
#	find({ 'wanted' => \&findfunc, 'no_chdir' => 1 }, $inbox);
#}

if ($uwmaildir ne '') {
	find({ 'wanted' => \&findfunc, 'no_chdir' => 1 }, $uwmaildir);
}

if ($subscriptions ne '') {
	if (open(SUBS, '<', $subscriptions)) {
		eval {
			open(NEWSUBS, '>', "$maildir/subscriptions") || die "Can't open $maildir/subscriptions";
		};
		if ($@) {
			warn $@;
		} else {
			my $line;
			while ($line = <SUBS>) {
				$line =~ s/^\Q$uwmaildir\E\///;
				if ($separator ne '/') {
					$line =~ s/\Q$separator/$replacement/g;
					$line =~ s/\//$separator/g;
				}
				print NEWSUBS $line;
			}
		}
		close(SUBS);
		close(NEWSUBS);
	} else {
		warn "Can't open $subscriptions"
	}
}

print "Total conversion: $totalmsgs messages\n" if ($opts{'v'});
