#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Encode;
use HTTP::Tiny;
use HTML::Entities;
use YAML qw(DumpFile);

sub parse_xhtml {
    my ($buf) = @_;
    my @output;

    while (1) {
        last if $buf eq ''; # 何も残ってなければファイル末尾なので終了

        # タグ以前のテキストを出力
        my $tag_begin = index($buf, '<');
        if ($tag_begin < 0) {
            last;
        } elsif ($tag_begin > 0) {
            my $text = substr($buf, 0, $tag_begin, '');
            push @output, decode_entities($text);
        }

        # タグだと思ったらコメントだった場合の処理
        if ($buf =~ m{\A<!--}s) {
            # コメントの中味を出力
            my $comment_end = index($buf, '-->');
            my $comment;
            if ($comment_end >= 0) {
                $comment = substr(substr($buf, 0, $comment_end + 3, ''), 4, -3);
            } else {
                # ケツ切れコメントの場合
                $comment = substr($buf, 4);
                $buf = '';
            }
            push @output, [ '--', { value => $comment }];
            next;
        }
        # タグだと思ったらCDATAだった場合の処理
        if ($buf =~ m{\A<!\[CDATA\[}s) {
            # コメントの中味を出力
            my $cdata_end = index($buf, ']]>');
            my $cdata;
            if ($cdata_end >= 0) {
                $cdata = substr($buf, 0, $cdata_end + 3, '');
            } else {
                # ケツ切れCDATAの場合
                $cdata = $buf;
                $buf = '';
            }
            push @output, $cdata;
            next;
        }

        # タグの処理
        my $tag_end = index($buf, '>');
        my $tag;
        if ($tag_end >= 0) {
            $tag = substr(substr($buf, 0, $tag_end + 1, ''), 1, -1);
        } else {
            # ケツ切れタグの場合
            $tag = substr($buf, 1);
            $buf = '';
        }
        my ($tag_name, $tag_attrs) = split(/\s+/, $tag, 2);
        if (!defined($tag_name)) {
            warn "no tag '$tag' : buf{$buf}";
        }
        my %attr;
        if (defined($tag_attrs)) {
            if ($tag_attrs =~ m{/$}s) {
                $tag_name = "$tag_name/";
                $tag_attrs = substr($tag_attrs, 0, -1);
            }
            while ($tag_attrs =~ m{(\w+)=(?:"([^"]*)"|'([^'])')}sg) {
                my $attr_name = $1;
                my $attr_value = $2 // $3;
                $attr{$attr_name} = decode_entities($attr_value);
            }
        }
        push @output, [ $tag_name, \%attr ];
    }
    return \@output;

}

my %link_map;
my @links;
my $body = 0;
sub convert_md {
    my $text = '';
    my ($elements, $end_tag) = @_;

    while (@$elements) {
        my $append = '';
        my $part = shift @$elements;
        if (ref($part) eq 'ARRAY') {
            my ($name, $attr) = @$part;
            if (!defined($name)) {
                warn Dumper($part);
            } elsif ($name eq 'body') {
                $body++;
                next;
            } elsif ($name eq '/body') {
                $body--;
                next;
            }
            next if $body < 2;
            if (defined($end_tag) && $name eq $end_tag) {
                last;
            } elsif ($name eq 'p') {
                $append .= "\n" if $text !~ /\n\z/s;
                $append .= convert_md($elements, '/p');
                $append .= "\n";
            } elsif ($name eq 'pre') {
                my $t = convert_md($elements, '/pre');
                if ($t !~ /\n\z/s) {
                    $t .= "\n";
                }
                $append .= "\n" if $text !~ /\n\z/s;
                $append .= "```$t```\n";
            } elsif ($name eq 'a') {
                if (exists($attr->{class})) {
                    if ($attr->{class} eq 'wiki-anchor') {
                        convert_md($elements, '/a'); # wiki-anchorの中は無視(たぶん空だけど)
                    } elsif ($attr->{class} eq 'wiki-page') {
                        my $href = $attr->{href};
                        if ($href =~ m{^doku.php\?id=reference:(.*)}) {
                            my $page = $1;
                            $href = $page;
                            if (exists($link_map{$page})) {
                                $href = $link_map{$page};
                            } else {
                                $link_map{$page} = $page;
                                push @links, $page;
                            }
                        }

                        my $t = convert_md($elements, '/a');
                        $append .= "[$t]($href)"
                    }
                }
            } elsif ($name =~ m{^h(\d)$}) {
                my $depth = $1;
                if ($depth == 5) {
                    $append .= "\n" if $text !~ /\n\z/s;
                    $append .= convert_md($elements, "/$name");
                    $append .= "\n";
                } else {
                    $append .= "\n" if $text !~ /\n\z/s;
                    $append .= ('#'x$depth).' ';
                    $append .= convert_md($elements, "/$name");
                }
            } elsif ($name eq 'img/'  && $attr->{src} =~ qr{^lib/exe/fetch.php\?media=reference:ch_u(\d+).png$}) {
                if ($1 == 2654) {
                    $text .= '**[!!]**';
                } elsif ($1 == 2658) {
                    $text .= '**[!]**';
                }
            } elsif ($name eq 'table') {
                $append .= "\n" if $text !~ /\n\z/s;
                my @rows;
                while (@$elements) {
                    my $p = shift @$elements;
                    if (ref($p) eq 'ARRAY') {
                        if ($p->[0] eq 'tr') {
                            my @cols;
                            while (@$elements) {
                                my $p = shift @$elements;
                                if (ref($p) eq 'ARRAY') {
                                    if ($p->[0] eq 'td') {
                                        my $t = convert_md($elements, '/td');
                                        push @cols, $t;
                                    } elsif ($p->[0] eq 'th') {
                                        my $t = convert_md($elements, '/th');
                                        push @cols, $t;
                                    } elsif ($p->[0] eq '/tr') {
                                        last;
                                    }
                                }
                            }
                            push @rows, \@cols;
                        } elsif ($p->[0] eq '/table') {
                            last;
                        }
                    }
                }
                my $align = 0;
                for my $cols (@rows) {
                    if (!$align) {
                        $append .= "|".join('|', ('') x scalar(@$cols))."|\n";
                        $append .= "|".join('|', ('---') x scalar(@$cols))."|\n";
                        $align = 1;    
                    }
                    $append .= "|".join('|', @$cols)."|\n";
                }
            } elsif ($name eq 'ul') {
                $append .= "\n" if $text !~ /\n\z/s;
                while (@$elements) {
                    my $p = shift @$elements;
                    if (ref($p) eq 'ARRAY') {
                        if ($p->[0] eq '/ul') {
                            last;
                        } elsif ($p->[0] eq 'li') {
                            my $t = convert_md($elements, '/li');
                            $append .= '* '.$t;
                            $append .= "\n" if $t !~ /\n\z/s;
                        }
                    }
                }
                $append .= "\n";
            } elsif ($name eq 'ol') {
            } elsif ($name eq 'br/') {
                $append .= "  \n";
            } elsif ($name eq 'hr/') {
                $append .= "\n----\n";
            } else {
                $append .= "<$name>";
            }
        } else {
            next if $body < 2;
            $append .= $part;
        } 
        $text .= $append;
    }
    return $text;
}

my $url_base = 'https://sup4.smilebasic.com/doku.php?do=export_xhtml&id=reference:';
push @links, 'top';
$link_map{top} = 'index';
for (my $i = 0; $i < scalar(@links); $i++) {
    my $page = $links[$i];
    my $file = 'docs/'.$link_map{$page}.'.md';
    print encode_utf8("loading $page\n");
    my $res = HTTP::Tiny->new->get(encode_utf8($url_base.$page));
    die "can't fetch page '$page'" unless $res->{success};
    my $elements = parse_xhtml(decode_utf8($res->{content}));
    open(my $fh, '>:encoding(UTF-8)', $file) or die $!;
    print $fh convert_md($elements);
    close($fh);
}

my $config = {
    site_name => 'プチコン4 Reference Manual',
    theme => 'readthedocs',
    nav => [ map { "$_.md" } map { $link_map{$_} } @links ],
};
DumpFile('mkdocs.yml', $config);
