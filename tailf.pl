#! /usr/bin/perl

use strict;
use warnings;

use Time::HiRes qw/usleep/;
use Term::ANSIColor qw/:constants/;

our $VERSION = 0.01;


sub hi ($);
sub iterate ();
sub flush_buff ();
sub is_buffer ();
sub clear_screen ();
sub position_in_file ();


die unless @ARGV && -r $ARGV[0];

my $file_name = shift;

my $file_size = -s $file_name;
my $move_length = 500;

my $delay = 50_000;
my $time_wo_new_lines = 0;
my $max_time_wo_flush = 100_000;
my $max_time_wo_clear = 550_000;

my $n = shift || 10;
my $begin_re = qr/\[[a-z]{3} [a-z]{3} \d{2} \d{2}:\d{2}:\d{2} \d{4}\]/i;

my $last_line;


open F, "<$file_name" or die "Can't open file $file_name\n";

position_in_file;

while (1) {
      iterate while <F>;

      usleep $delay;
      $time_wo_new_lines += $delay;

      flush_buff if $time_wo_new_lines >= $max_time_wo_flush;
}
close F;


sub position_in_file () {
      my $lines = 0;
      my @buff;
      my $iteration = 0;
      local $/ = \$move_length;

      while ($lines < $n) {
            seek F, -($move_length * ++$iteration), 2;
            push @buff, scalar <F>;

            $lines += length join '', $buff[-1] =~ m/(\n)$begin_re /oig;
      }

      my $p = -1;
      my $i = $lines - $n + 1;
      while ($i && ($p = index $buff[-1], "\n", $p + 1) > -1) {
            $i-- if substr($buff[-1], $p + 1) =~ m/^$begin_re/i;
      }

      $buff[-1] = substr $buff[-1], $p + 1;

      iterate for map {"$_\n"} split "\n", join '', reverse @buff;

      seek F, 0, 2;
}


{  my $buff = '';

sub is_buffer () {!!$buff}

sub iterate () {
      local $_ = $_;

      clear_screen 
            if $time_wo_new_lines > $max_time_wo_clear && !is_buffer;

      $time_wo_new_lines = 0;

      flush_buff if m/^$begin_re/;

      $buff .= $_;
}

sub flush_buff () {
      return unless defined $buff && length $buff;
      hi $buff;
      $buff = '';
} }

sub hi ($) {
      local $_ = shift;
      my $text_copy = $_;
      my $eq;

      FOOBAR: {
            if (defined $last_line && $last_line eq $_) {
                  $eq = 1;
                  print BOLD.RED.'REPEATING PREVIOUS LINE'.RESET, v10;

                  last;
            }

            print v10;

            HIGHS: {
                  if (m/^\[([a-z]{3}) ([a-z]{3}) (\d{2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})\] /ois) {
                        printf '[%s %s %s %s%s:%s:%s %s%s] ',
                              $1, $2, $3, BOLD.YELLOW, $4, $5, $6, RESET, $7;

                        $_ = $';


                        if (m/^\[perl_(warn|emerg)\] /ois) {
                              printf '[%s%sperl_%s%s] ',
                                    $1 eq 'emerg' ? BOLD : '', RED, $1, RESET;

                              $_ = $';


                              if (m/\[([^\]]+)\] /ois) {
                                    printf '[%s%s%s] ',
                                          GREEN, $1, RESET;

                                    $_ = $';

                                    #INFO ... || index($_, "\n") < length($s) - 1
                                    print v10 if 50 < length $_ || m/\n./;

                                    if (m/^(\d+)[,.](\d{1,3})(\d*) sec/ois) {
                                          #FIXME \n
                                          printf "%s%d.%03d%s%s s", ($1 > 0 || $2 > 10) ? BOLD.RED : YELLOW, $1, $2, RESET, $3;
                                          $_ = $';

                                          #FIXME last FOOBAR
                                          last;

                                    } elsif (m/^DBD::mysql::st execute failed/ois) {
                                          print BOLD, RED, $&, RESET;
                                          #print RED, $', RESET;
                                          $_ = $';
                                          last;
                                    }
                              }
                        }
                  }
            }


            my $def_color  = CYAN;

            #TODO highlight parts here

            s/\bat (\S+) line (\d+)\./'at '.$1.' line '.RED.$2.RESET.$def_color.'.'/eg;

            s{([-a-z._/]+/)?([^/]+\.(?:pm|pl|tpl|cgi))}[YELLOW.$1.BOLD.YELLOW.$2.RESET.$def_color]ieg
                  or
            s/\bHealth_[a-z_]+\b/MAGENTA.$&.RESET.$def_color/eig
                  and
            s/\b(GROUP BY|FROM|ON|SELECT|UPDATE|INSERT|DELETE|WHERE|ORDER BY|(?:LEFT )?JOIN)\b/RED.$1.RESET.$def_color/eig;

            print $def_color, $_, RESET;
            #print "### BEGIN ###\n$_### END ###\n";
      }

      $last_line = $text_copy;
}

sub size_changed () {
      my $old_size = $file_size;
      $file_size = -s $file_name;

      $file_size != $old_size
}

{ my $cleaner; sub clear_screen () { $cleaner ||= `clear`; print "CLEARING SCREEN...\n", v10 x 40; $cleaner } }
