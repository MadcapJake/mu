
use v6-alpha;

=begin

This visitor attaches 'env' closures to the AST

=end

# TODO:
# - keep the type info

class KindaPerl6::Visitor::CreateEnv {

    #use Pad;
    has $.env;
    has $.lexicals;

    method visit ( $node ) {

        #say "Processing ", $node;

        if ( $node.isa( 'Lit::Code' ) ) {
            my $temp_env      := $.env;
            my $temp_lexicals := $.lexicals;

            # get the lexical names from the body
            #$.env := undef;
            $.lexicals := [ ];
            my $body := KindaPerl6::Traverse::visit( self, $node.body );

            # create this pad
            my $node2 := ::Lit::Code(
                pad   => ::Pad(
                    outer    => $temp_env,
                    lexicals => $.lexicals
                ),
                state => $node.state,
                sig   => $node.sig,
                body  => $node.body,
            );

            # revisit in order to create the inner pads
            $.env := $node2.pad;
            $.lexicals := [ ];
            $node2.body( KindaPerl6::Traverse::visit( self, $node.body ) );

            $.env      := $temp_env;
            $.lexicals := $temp_lexicals;
            return $node2;
        };

        if  (  $node.isa( 'Decl' )
            && $node.decl eq 'my'
            )
        {
            # XXX - expand Bind/Assign
            push @($.lexicals), $node;
            return $node.var;
        };

        return;
    };

}


=begin

=head1 AUTHORS

The Pugs Team E<lt>perl6-compiler@perl.orgE<gt>.

=head1 SEE ALSO

The Perl 6 homepage at L<http://dev.perl.org/perl6>.

The Pugs homepage at L<http://pugscode.org/>.

=head1 COPYRIGHT

Copyright 2007 by Flavio Soibelmann Glock and others.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=end
