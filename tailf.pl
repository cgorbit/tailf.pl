#! /usr/bin/perl

use strict;
use warnings;

use Time::HiRes qw/usleep gettimeofday tv_interval/;
use Term::ANSIColor qw/:constants color/;

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

#$file_size = -s $file_name

while (1) {
      iterate while <F>;
      #warn "HERE\n";

      usleep $delay;
      $time_wo_new_lines += $delay;

      flush_buff if $time_wo_new_lines >= $max_time_wo_flush;
}
close F;


sub position_in_file () {
      my $lines = 0;
      my $buff = '';
      my $iteration = 0;
      local $/ = \$move_length;
      my $n = $n;

      seek F, 0, 2;
      my $initial_pos = tell F;

      my $last;

      while ($lines < $n) {
            #warn "$lines vs $n\n";
            my $offset = $move_length * (++$iteration > 1 ? 2 : 1);

            #warn 'WILL SEEK TO ', tell(F) - $offset, v10;
            if (tell(F) - $offset < 0) {
                  #warn "SEEK TO BEGINNING\n";
                  seek F, 0, 0;
                  $/ = \($file_size % $move_length);
                  #warn 'WILL READ ', ${$/}, v10;
                  $last = 1;
                  #warn "LAST\n" if $last;
            } else {
                  seek F, -$offset, 1 or do {
                        #warn "CAN'T SEEK\n";
                        $n = $lines;
                        last;
                  }
            }

            $buff = <F> . $buff;

            $lines = scalar( () = $buff =~ m/(\n|^)$begin_re /soig );

            $n = $lines if $last;
      }
      #warn "\$lines = $lines\n";

      my $p = -1;
      my $i = $lines - $n + $buff =~ /\A$begin_re /soi ? 0 : 1;
      while ($i && ($p = index $buff, "\n", $p + 1) > -1) {
            $i-- if substr($buff, $p + 1) =~ m/^$begin_re/i;
      }
      #warn "\$p = $p\n";
      #exit;

      iterate for map {"$_\n"} split "\n", substr $buff, $p + 1;

      seek F, $initial_pos, 0;
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
#my $t0 = [gettimeofday];
      hi $buff;
#warn "TIME: ", tv_interval($t0), v10;
      $buff = '';
} }

sub hi ($) {
      local $_ = shift;
      my $text_copy = $_;
      my $eq;
      my $out = '';

      FOOBAR: {
            if (defined $last_line && $last_line eq $_) {
                  $eq = 1;
                  $out .= '<bold red>REPEATING PREVIOUS LINE</end>' . v10;

                  last;
            }

            $out .= v10;

            HIGHS: {
                  if (m/^\[([a-z]{3}) ([a-z]{3}) (\d{2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})\] /ois) {
                        $out .= sprintf '[%s %s %s %s%s:%s:%s %s%s] ',
                              $1, $2, $3, '<bold yellow>', $4, $5, $6, '</end>', $7;

                        $_ = $';

                        s/&/&amp;/g;
                        s/</&lt;/g;
                        s/>/&gt;/g;

                        if (m/^\[(perl_)?(warn|emerg)\] /ois) {
                              $out .= sprintf '[<%s%s%s%s%s] ',
                                    $1 eq 'emerg' ? 'bold ' : '', 'red>', $1, $2, '</end>';

                              $_ = $';


                              if (m/\[([^\]]+)\] /ois) {
                                    $out .= sprintf '[%s%s%s] ',
                                          '<green>', $1, '</end>';

                                    $_ = $';

                                    #INFO ... || index($_, "\n") < length($s) - 1
                                    $out .= v10 if 50 < length $_ || m/\n./;

                                    if (m/^(\d+)[,.](\d{1,3})(\d*) sec/ois) {
                                          #FIXME \n
                                          $out .= sprintf "%s%d.%03d%s%s s", ($1 > 0 || $2 > 10) ? '<bold red>' : '<yellow>', $1, $2, '</end>', $3;
                                          $_ = $';

                                          #FIXME last FOOBAR
                                          last;

                                    } elsif (m/^DBD::mysql::st execute failed/ois) {
                                          $out .= "<bold red>$&</end>";
                                          $_ = $';
                                          last;
                                    }
                              }
                        }
                  }
            }


            #TODO highlight parts here

            s/\bat (\S+) line (\d+)\./at $1 line <red>$2<\/end>./g;

            s{([-a-z._/]+/)?([^/]+\.(?:pm|pl|tpl|cgi))}[<yellow>$1</end><bold yellow>$2</end>]ig
                  or
            s/\bHealth_[a-z_]+\b/<magenta>$&<\/end>/ig
                  and
            s/\b(GROUP BY|FROM|ON|SELECT|UPDATE|INSERT|DELETE|WHERE|ORDER BY|(?:LEFT )?JOIN)\b/<red>$1<\/end>/ig;

            s/\n$//;
            $out .= $_ . v10;
      }

      my @colors;
      $out = join '', map {
            if ($_ eq '</end>') {
                  pop @colors;
                  RESET.color( $colors[-1] || 'reset' );
            } elsif (m/<([^>]+)>/) {
                  push @colors, $1;
                  color $1;
            } else {
                  $_
            }
      } split /(<\/?[^>]+>)/, $out;

      s/&lt;/</g;
      s/&gt;/>/g;
      s/&amp;/&/g;

      print $out;

      $last_line = $text_copy;
}

sub size_changed () {
      my $old_size = $file_size;
      $file_size = -s $file_name;

      $file_size != $old_size
}

{ my $cleaner; sub clear_screen () { $cleaner ||= `clear`; print "CLEARING SCREEN...\n", v10 x 40; $cleaner } }
