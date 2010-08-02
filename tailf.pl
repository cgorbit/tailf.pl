#! /usr/bin/perl

use strict;
use warnings;

#use POSIX qw/strftime/;
use Time::HiRes qw/usleep gettimeofday tv_interval/;
use Term::ANSIColor qw/:constants color/;

our $VERSION = 0.01;


sub hi ($);
sub iterate ();
sub flush_buff ();
sub is_buffer ();
sub clear_screen ();
sub position_in_file ();
sub get_term_columns ();


die unless @ARGV && -r $ARGV[0];

my $file_name = shift;

my $file_size = -s $file_name;
my $move_length = 1000;

my $delay = 50_000;
my $time_wo_new_lines = 0;
my $max_time_wo_flush = 100_000;
my $max_time_wo_clear = 550_000;

my $n = shift || 10;
my $begin_re = qr/\[[a-z]{3} [a-z]{3} \s?\d{1,2} \d{2}:\d{2}:\d{2} \d{4}\]/i;

my ($last_line, $last_was_long, $last_blocks_width);


open F, "<$file_name" or die "Can't open file $file_name\n";

position_in_file;

#$file_size = -s $file_name

while (1) {
      # Clear end-of-file condition of the handle
      # See perldoc perlfaq5 "How do I do a "tail -f" in perl?"
      seek F, 0, 1;
      iterate while <F>;

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

            $n = $lines if $last && $n > $lines;

            last if $last;
      }
      #warn "\$lines = $lines\n";
      #warn "\$n = $n\n";

      my $p = -1;
      my $i = $lines - $n + ($buff =~ /\A$begin_re /soi ? 0 : 1);
      while ($i && ($p = index $buff, "\n", $p + 1) > -1) {
            #warn "WITH \$i = $i\n";
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

      flush_buff if m/^$begin_re/o;

      $buff .= $_;
}

sub flush_buff () {
      return unless defined $buff && length $buff;
      hi $buff;
      $buff = '';
      1
} }

sub hi ($) {
      local $_ = shift;
      my $text_copy = $_;
      my $eq;
      my $out = '';

      my ($blocks_width, $was_long);

      FOOBAR: {
            if (defined $last_line && $last_line eq $_) {
                  $eq = 1;
                  $out .= '<bold red>REPEATING PREVIOUS LINE</end>' . v10;

                  last;
            }

            $out .= v10;

            HIGHS: {
                  my $current_position = 1;

                  if (m/^\[([a-z]{3}) ([a-z]{3}) (\s?\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})\] /ois) {
                        $current_position += length $&;

                        $out .= sprintf '[%s %s %s %s%s:%s:%s %s%s] ',
                              $1, $2, $3, '<bold yellow>', $4, $5, $6, '</end>', $7;

                        $_ = $';

                        s/&/&amp;/g;
                        s/</&lt;/g;
                        s/>/&gt;/g;

                        if (m/^\[(perl_)?(warn|emerg)\] /ois) {
                              $current_position += length $&;

                              $out .= sprintf '[<%s%s%s%s%s] ',
                                    $2 eq 'emerg' ? 'bold ' : '', 'red>', $1, $2, '</end>';

                              $_ = $';


                              if (m/\[([^\]]+)\] /ois) {
                                    $current_position += length $&;
                                    $blocks_width = $current_position - 1;

                                    $out .= sprintf '[%s%s%s] ',
                                          '<green>', $1, '</end>';

                                    $_ = $';

                                    my $rest = get_term_columns - $current_position + 1;
                                    #FIXME length $_ > $rest + 1, because $_ contains \n
                                    if (length $_ > $rest or m/\n./) {
                                          $out .= v10;
                                          $was_long = 1;
                                    } else {
                                          $was_long = 0;
                                    }

                                    if (m/^(\d+)[,.](\d{1,3})(\d*) sec$/ois) {
                                          #FIXME \n

                                          $out = sprintf "%s%s%d.%03d%s%s s",
                                                (defined $last_line && !$last_was_long)
                                                      ? v32 x $last_blocks_width 
                                                      : 'Execution time: ',
                                                ($1 > 0 || $2 > 10) ? '<bold red>' : '<yellow>',
                                                $1, $2, '</end>', $3;

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

            #FIXME (\.|: |$)
            s/\bat (\S+) line (\d+)(\.|: )/($3 eq '.' ? "\n\t" : '')."<white>at<\/end> $1 <white>line<\/end> <red>$2<\/end>$3".($3 eq ': ' ? "\n\t" : '')/eg;

            s{([-a-z._/]+/)?([^/]+\.(?:pm|pl|tpl|cgi))}[<yellow>$1</end><bold yellow>$2</end>]ig
                  or
            # TODO s/Health/$ENV{NAME_PRJ}/
            s/\bHealth_[a-z_]+\b/<magenta>$&<\/end>/ig
                  and
            s/\b(LIMIT|SQL_CALC_FOUND_ROWS|GROUP BY|FROM|ON|SELECT|UPDATE|INSERT|DELETE|WHERE|ORDER BY|(?:(?:LEFT|INNER|RIGHT) )?JOIN)\b/<red>$1<\/end>/ig;

            s/\n$//;
            $out .= '<white bold>'. $_ . '</end>' . v10;
      }

      my @colors;
      $out = join '', map {
            if ($_ eq '</end>') {
                  pop @colors;
                  RESET.color( $colors[-1] || 'reset' );
            } elsif (m/<([^>]+)>/) {
                  push @colors, $1;
                  RESET.color($1);
            } else {
                  $_
            }
      } split /(<\/?[^>]+>)/, $out;

      $out =~ s/&lt;/</g;
      $out =~ s/&gt;/>/g;
      $out =~ s/&amp;/&/g;

      print $out;

      $last_line = $text_copy;
      $last_was_long = $was_long;
      $last_blocks_width = $blocks_width;
}

sub size_changed () {
      my $old_size = $file_size;
      ($file_size = -s $file_name) != $old_size
}

{ my $cleaner;
sub clear_screen () {
      $cleaner ||= `clear`;
      my $time = sprintf "%02d:%02d:%02d", (localtime)[2,1,0];

      $last_line = '';
      print "\n\nCLEARING SCREEN at $time...\n", v10 x 40; $cleaner
} }

sub get_term_dimensions () {
      #my ($rows, $columns) 
      (`stty -a` =~ m/\brows (\d+); columns (\d+);/)[0, 1]
}

sub get_term_columns () { (get_term_dimensions)[1] }
