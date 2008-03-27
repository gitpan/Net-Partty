#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Path::Class;
use Getopt::Long;
use Pod::Usage;

use lib file( $FindBin::RealBin, 'lib' )->stringify,
        file( $FindBin::RealBin, '..', 'lib' )->stringify;
use Net::Partty;

use IO::Pty;
use IO::Select;
use Term::ReadKey;

my $opts = {};
Getopt::Long::GetOptions(
    '--help'                => \my $help,
    '--session_name=s'      => \$opts->{session_name},
    '--message=s'           => \$opts->{message},
    '--writable_password=s' => \$opts->{writable_password},
    '--readonly_password=s' => \$opts->{readonly_password},
    '--kill_guest'          => \$opts->{kill_guest},
) or pod2usage(2);
Getopt::Long::Configure("bundling");
pod2usage(-verbose => 2) if $help;

for my $key (keys %{ $opts }) {
    delete $opts->{$key} unless $opts->{$key} || $key eq 'readonly_password';
}
$opts->{readonly_password} ||= '';

use YAML;warn Dump($opts);

my $partty = Net::Partty->new;
eval { $partty->connect(%{ $opts }) };
pod2usage(-verbose => 2) if $@;
$ENV{PARTTY_SESSION} = $opts->{session_name};


my $master = IO::Pty->new;
my $slave = $master->slave;
local $SIG{CHLD} = sub {
    ReadMode 0, \*STDIN;
    print "\n";
    exit;
};
local $SIG{PIPE} = sub {
    die "SIGPIPE";
};

my $pid = fork;
if ($pid < 0) {
    # error
    close $master;
    close $slave;
    die;
} elsif ($pid) {
    # parent
    close $slave;
} else {
    # child
    close $master;

    # like dup2
    open STDOUT, '>&', $slave or die $!;
    open STDERR, '>&', $slave or die $!;
    open STDIN, '<&', $slave or die $!;

    close $slave;
    my $shell = $ENV{SHELL} || '/bin/sh';
    exit exec $shell, '-i';
}

ReadMode 'raw', \*STDIN;
$master->blocking(0);
STDIN->blocking(0);
STDOUT->blocking(0);
$partty->sock->blocking(0);

my $select = IO::Select->new;
$select->add($master);
$select->add(\*STDIN);
$select->add($partty->sock);

my $m_fno = fileno($master);
my $i_fno = fileno(\*STDIN);
my $p_fno = fileno($partty->sock);

while (1) {
    my @ready = $select->can_read(10);
    next unless @ready;
    for my $fh (@ready) {
        my $fno = fileno($fh);
        if ($fno == $m_fno) {
            my $len = $fh->sysread(my $buf, 4096);
            STDOUT->syswrite($buf, $len);
            $partty->can_write(100);
            $partty->sock->syswrite($buf, $len);
        } elsif ($fno == $i_fno) {
            my $len = $fh->sysread(my $buf, 4096);
            $master->syswrite($buf, $len);
        } elsif ($fno == $p_fno) {
            my $len = $fh->sysread(my $buf, 4096);
            $master->syswrite($buf, $len) unless $opts->{kill_guest};
        }
    }
}
print "end\n";

__END__

=encoding utf8

=head1 SYNOPSIS

    $ pertty.pl 

    Options:
        -s <session name>        session name
        -m <message>             message in a word
        -w <operation password>  password to operate the session
        -r <view password>       password to view the session
        -k                       disable all gust operation regardless of operation password

=head1 UNSUPPORTED

        -c <lock character>      control key to lock guest operation (default: ']')

=head1 TODO

    terminal size を継承する
    
