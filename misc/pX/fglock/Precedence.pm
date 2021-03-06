﻿package Pugs::Grammar::Precedence;

# Documentation in the __END__
use 5.006;
use strict;
use warnings;

use Parse::Yapp;
use Data::Dump::Streamer;
use Digest::MD5 'md5_hex';

my $cache;
eval {
    require Cache::FileCache;
    $cache = new Cache::FileCache( { 'namespace' => 'v6-precedence' } );
};

my %relative_precedences = (
    tighter => sub {
        my $new_level = [ $_[2] ];
        $_[0]->{op}{$_[2]->{name}}{level} = $new_level;
        $_[0]->{op}{$_[2]->{name}}{index} = $_[2]->{index};
        splice( @{$_[0]->{levels}}, $_[1], 0, $new_level );
    },
    looser  => sub {
        my $new_level = [ $_[2] ];
        $_[0]->{op}{$_[2]->{name}}{level} = $new_level;
        $_[0]->{op}{$_[2]->{name}}{index} = $_[2]->{index};
        splice( @{$_[0]->{levels}}, $_[1]+1, 0, $new_level );
    },
);

# note: S06 - 'chain' can't be mixed with other types in the same level
my %rule_templates = (
    prefix_non =>        
        "'index' exp         \n" .
        "\t{ \$_[0]->{out}= {fixity => 'prefix', op1 => \$_[1], exp1 => \$_[2],} }", 
    circumfix_non =>     
        "'index' exp 'name2' \n" .
        "\t{ \$_[0]->{out}= {fixity => 'circumfix', op1 => \$_[1], op2 => \$_[3], exp1 => \$_[2],} }\n" .  
        "\t | 'index' 'name2' \n" .
        "\t{ \$_[0]->{out}= {fixity => 'circumfix', op1 => \$_[1], op2 => \$_[2] } }",  
    infix_right =>       
        "exp 'index' exp     \n" .
        "\t{ \$_[0]->{out}= {fixity => 'infix', op1 => \$_[2], exp1 => \$_[1], exp2 => \$_[3],} }",
    postfix_non =>       
        "exp 'index'         \n" .
        "\t{ \$_[0]->{out}= {fixity => 'postfix', op1 => \$_[2], exp1 => \$_[1],} }", 
    postcircumfix_non => 
        "exp 'index' exp 'name2' \n" .
        "\t{ \$_[0]->{out}= {fixity => 'postcircumfix', op1 => \$_[2], op2 => \$_[4], exp1 => \$_[1], exp2 => \$_[3],} } \n" . 
        "\t | exp 'index' 'name2' \n" .
        "\t{ \$_[0]->{out}= {fixity => 'postcircumfix', op1 => \$_[2], op2 => \$_[3], exp1 => \$_[1], } }", 
    infix_left =>        
        "exp 'index' exp     \n" .
        "\t{ \$_[0]->{out}= {fixity => 'infix', op1 => \$_[2], exp1 => \$_[1], exp2 => \$_[3],} }", 
    infix_non =>         
        "exp 'index' exp     \n" .
        "\t{ \$_[0]->{out}= {fixity => 'infix', op1 => \$_[2], exp1 => \$_[1], exp2 => \$_[3],} }", 
    ternary_non =>       
        "exp 'index' exp 'name2' exp \n" .
        "\t{ \$_[0]->{out}= {fixity => 'ternary', op1 => \$_[2], op2 => \$_[4], exp1 => \$_[1], exp2 => \$_[3], exp3 => \$_[5],} }",
        
    # XXX
    #infix_chain =>       
    #    "exp 'name' chain_right  \n" .
    #    "\t{ \$_[0]->{out}= {op1 => 'name', exp1 => \$_[1], exp2 => \$_[3],} }",
    #infix_list =>        
    #    "exp 'name' list_right \n" .
    #    "\t{ \$_[0]->{out}= {op1 => 'name', exp1 => \$_[1], exp2 => \$_[3],} }", 
);

sub new {
    my $class = shift;
    my $self = { levels => [], @_ };
    bless $self, $class; 
}

our $op_count = '000';
sub add_op {
    my ($self, $opt) = @_;
    print "adding $opt->{name} is $opt->{precedence} $opt->{other}\n";
    $opt->{assoc}  = 'non'    unless defined $opt->{assoc};
    $opt->{fixity} = 'prefix' unless defined $opt->{fixity};
    $opt->{index}  = 'OP' . $op_count++;
    #my $fixity = $opt->{fixity};
    #$fixity .= '_' . $opt->{assoc} if $opt->{fixity} eq 'infix';
    if ( defined $opt->{other} ) {
        if ( $opt->{precedence} eq 'equal' ) {
            # 0=self, 1=level, 2=new op, 3=equal op
            my $level = $self->{op}{$opt->{other}}{level};
            # my $index = $self->{op}{$opt->{other}}{index};
            print "adding equal precedence to $opt->{other}: $opt->{name} \n";
            for my $other ( @$level ) {
                print "  has $other->{name} $other->{index} \n";
                next unless $other->{fixity} eq $opt->{fixity};
                print "    same fixity $other->{fixity}\n";
                next unless $other->{assoc} eq $opt->{assoc};
                print "    same assoc $other->{assoc}\n";
                $opt->{index} = $other->{index};
                $self->{op}{$opt->{name}}{level} = $level;
                $self->{op}{$opt->{name}}{index} = $other->{index};
                return;
            }
            $self->{op}{$opt->{name}}{level} = $level;
            $self->{op}{$opt->{name}}{index} = $opt->{index};
            push @$level, $opt;
            return;
        }
        else {
            my $other_level = $self->{op}{$opt->{other}}{level};
            #print "  other level: $other_level \n";
            for my $level ( 0 .. $#{$self->{levels}} ) {
                # XXX comparing pointers
                print "  other level: $other_level cmp $self->{levels}[$level] \n";
                if ( $self->{levels}[$level] eq $other_level ) {
                    #for my $other ( @{$self->{levels}[$level]} ) {
                    #if ( $other->{name} eq $opt->{other} ) { 
                        #print "pos $level at $opt->{precedence} $opt->{other}\n";
                        $relative_precedences{$opt->{precedence}}->($self, $level, $opt);
                        #print "Precedence table: ", Dump( $self );
                        return;
                    #}
                }
            }
        }
    }
    if ( ! defined $opt->{precedence} ) {
        my $new_level = [ $opt ];
        $_[0]->{op}{$opt->{name}}{level} = $new_level;
        $_[0]->{op}{$opt->{name}}{index} = $opt->{index};
        push @{$self->{levels}}, $new_level;
        return;
    }
    die "there is no precedence like ", $opt->{other};
}


sub add_to_list {
    my ( $op, $x, $y ) = @_;
    my @x = ($x);
    @x = @{$x->{list}} if exists $x->{list} && $x->{op1} eq $op;
    return { op1 => $op, list => [ @x, $y ], assoc => 'list' };
}

sub add_to_chain {
    my ( $op, $x, $y ) = @_;
    my @x = exists $x->{chain} ? @{$x->{chain}} : ($x);
    my @y = exists $y->{chain} ? @{$y->{chain}} : ($y);
    return { chain => [ @x, $op, @y ], assoc => 'chain' };
}

sub emit_yapp {
    my ($self) = @_;
    my $s;  # = "%{ my \$_[0]->{out}; %}\n";
    my $prec = "P000";
    my %seen;
    for my $level ( reverse 0 .. $#{$self->{levels}} ) {            
        my %assoc;
        for my $operator ( @{$self->{levels}[$level]} ) {
            push @{$assoc{ $operator->{assoc} }}, $operator;
        }
        for my $aaa ( keys %assoc ) {
            if ( @{$assoc{$aaa}} ) {
                my $a = $aaa;
                $a = 'nonassoc' if $a eq 'non';
                $a = 'left'     if $a eq 'list';
                $a = 'left'     if $a eq 'chain';
                $s .= "%$a ";
                for my $operator ( @{ $assoc{$aaa} } ) {
                    next if $seen{$operator->{index}};
                    $seen{$operator->{index}} = 1;
                    $s .= ' ' . 
                             "'$operator->{index}'" ;
                        # (( $aaa eq 'list' || $aaa eq 'chain' )
                        #     ? $operator->{index}
                        #     : "'$operator->{name}'" 
                        # );
                }
                $s .= 
                    " $prec" .
                    "\n";
                # $seen{$_->{index}} = 1 for @{$assoc{$_}};
                $prec++;
            }
        }
    }
    $s .= "%%\n" .
        "statement:  exp { return(\$_[0]->{out}) } ;\n";
            
    if ( defined $self->{header} ) {
        $s .= $self->{header};
    }
    else {
        $s .=     
            "exp:   NUM  { \$_[0]->{out}= \$_[1] }\n";
    }
    $prec = "P000";
    for my $level ( reverse 0 .. $#{$self->{levels}} ) {            
        my %assoc;
        for ( @{$self->{levels}[$level]} ) {
            push @{$assoc{ $_->{assoc} }}, $_;
        }
        for ( keys %assoc ) {
            if ( @{$assoc{$_}} ) {


                for my $op ( @{$assoc{$_}} ) {
                    if ( $op->{assoc} eq 'list' ) {
                        $s .= 
                            "    |  exp '$op->{index}' exp   %prec $prec\n" .
                            "        { \$_[0]->{out}= Pugs::Grammar::Precedence::add_to_list( '$op->{index}', \$_[1], \$_[3] ) } \n" ;
                        $s .= 
                            "    |  exp '$op->{index}'    %prec $prec\n" .
                            "        { \$_[0]->{out}= Pugs::Grammar::Precedence::add_to_list( '$op->{index}', \$_[1], { null => 1 } ) } \n" ;
                            # "        { \$_[0]->{out}= \$_[1] } \n" ;
                        next;
                    }
                    if ( $op->{assoc} eq 'chain' ) {
                        $s .= 
                            "    |  exp '$op->{index}' exp   %prec $prec\n" .
                            "        { \$_[0]->{out}= Pugs::Grammar::Precedence::add_to_chain( '$op->{index}', \$_[1], \$_[3] ) } \n" ;
                        $s .= 
                            "    |  exp '$op->{index}'    %prec $prec\n" .
                            "        { \$_[0]->{out}= Pugs::Grammar::Precedence::add_to_chain( '$op->{index}', \$_[1], { null => 1 } ) } \n" ;
                            # "        { \$_[0]->{out}= \$_[1] } \n" ;
                        next;
                    }
                    my $t = $rule_templates{"$op->{fixity}_$op->{assoc}"};
                    unless ( defined $t ) {
                        warn "can't find template for '$op->{fixity}_$op->{assoc}'";
                        next;
                    }
                    $t =~ s/$_/$op->{$_}/g for qw( name2 name index );
                    $t =~ s/\{ /%prec $prec { /;
                    $s .= "    |  $t \n" . 
                        # "\t%prec $prec\n" .
                        "\t/* $op->{name} $op->{fixity} $op->{assoc} */\n";
                }
                $prec++;
            }
        }
    }
    $s .= ";\n" .
        "%%\n";
    #print $s;
    return $s;
}

sub emit_grammar_perl5 {
    my $self = shift;
    my $g = $self->emit_yapp();
    print "emit_yapp: ", $g;

    my $digest = md5_hex($self->{grammar} . $g);
    my $cached;

    if ($cache && ($cached = $cache->get($digest))) {
	return $cached;
    }

    my $p = Parse::Yapp->new( input => $g );
    $cached = $p->Output( classname => $self->{grammar} );
    $cache->set($digest, $cached) if $cache;
    print "emit_grammar_perl5: ", length( $g ), " chars\n";

    return $cached;
}

sub exists_op { die "not implemented" };
sub delete_op { die "not implemented" };
sub get_op    { die "not implemented" };
sub inherit_category { die "not implemented" };
sub inherit_grammar  { die "not implemented" };
sub merge_category   { die "not implemented" };
sub code  { die "not implemented" }
sub match { die "not implemented" }
sub perl5 { die "not implemented" }

1;

__END__

=head1 NAME 

Pugs::Grammar::Precedence - Engine for Perl 6 Rule operator precedence

=head1 SYNOPSIS

  use Pugs::Grammar::Precedence;

  # example definition for "sub rxinfix:<|> ..."
  
  my $rxinfix = Pugs::Grammar::Precedence->new( 
    grammar => 'rxinfix',
  );
  $rxinfix->add_op( 
    name => '|',
    assoc => 'left',
    fixity => 'infix',
  );

Pseudo-code for usage inside a grammar:

    sub new_proto( $match ) {
        return ${$match<category>}.add_op( 
            name => $match<name>, 
            fixity => ..., 
            precedence => ...,
        );
    }

    rule prototype {
        proto <category>:<name> <options>
        { 
            return new_proto($/);
        }
    }

    rule statement {
        <category.parse> ...
    }

=head1 DESCRIPTION

This module provides an implementation for Perl 6 operator precedence.  

=head1 METHODS

=head2 new ()

Class method.  Returns a category object.

options:

=item * grammar => $category_name - the name of this category 
(a namespace or a Grammar name).

=head2 add_op ()

Instance method.  Adds a new operator to the category.

options:

=item * name => $operator_name - the name of this operator, such as '+', '*'

=item * name2 => $operator_name - the name of the second operator in
an operator pair, such as circumfix [ '(', ')' ] or ternary [ '??', '!!' ]. 

 # precedence=>'tighter', 
 #   tighter/looser/equiv 
 # other=>'+', 
 # fixity => 
 #  infix/prefix/circumfix/postcircumfix/ternary
 # assoc =>
 #  left/right/non/chain/list
 # rule=>$rule 
 #  (is parsed) 

=head1 AUTHORS

The Pugs Team E<lt>perl6-compiler@perl.orgE<gt>.

=head1 SEE ALSO

Summary of Perl 6 Operators: L<http://dev.perl.org/perl6/doc/design/syn/S03.html>

=head1 COPYRIGHT

Copyright 2006 by Flavio Soibelmann Glock and others.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
