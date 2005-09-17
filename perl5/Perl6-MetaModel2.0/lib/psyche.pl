#!/usr/bin/perl

use strict;
use warnings;

BEGIN { do "lib/pneuma.pl" };

# This is psyche, this creates ::Role

# From Answers.com:
# According to the Gnostics, the Demiurge was able to endow man 
# only with psyche (sensuous soul) — the pneuma (rational soul) 
# having been added by God.

# Naming Rationale:
# pneuma is the rational soul, really concreate and practical 
# things like Object, Package and Module. It was also created
# by God (which means it is part of the core model)
#
# psyche is the sensuous soul, meaning "relating to, or derived 
# from the senses". Think of Roles like you might think of Duck
# typing, but extend the metaphor to encompass all the senses. 
#
#   If it looks like a Duck, smells like a Duck, tastes like a Duck
#   feels like a Duck and quacks like a Duck, it must them implement
#   the Duck Role.
#
# The other point is that Demiurge endows man with the psyche, this
# sort of matches with how I plan to bootstrap Roles through Class.
# Which is not yet implemented but can be seen in MiniMetaModel_w_Roles.pl

$::Role = undef;

## ----------------------------------------------------------------------------
## Roles

# Questions on Role methods sent to p6l 
# - see recent thread: 'Concerning Roles and $?ROLE'

$::Role = $::Class->new('$:name' => 'Role');

$::Role->superclasses([ $::Module ]);

$::Role->add_attribute('@:roles'      => ::make_attribute('@:roles'));
$::Role->add_attribute('%:methods'    => ::make_attribute('%:methods'));
$::Role->add_attribute('%:attributes' => ::make_attribute('%:attributes'));

## methods

$::Role->add_method('add_method' => ::make_method(sub {
    my ($self, $label, $method) = @_;
    # NOTE: 
    # the $method here can be undefined, this is to allow
    # for methods which do not have an implementation. These
    # methods are then required to be implemented by the 
    # composing class.
    # (see A12/Class Composition with Roles/Declaration of Roles/Interfaces)
    ::opaque_instance_attrs($self)->{'%:methods'}->{$label} = (
        defined $method ? 
            ::wrap_role_method($method, $self)
            :
            ::make_stub_method());
}));

$::Role->add_method('get_method' => ::make_method(sub {
    my ($self, $label) = @_;
    ::opaque_instance_attrs($self)->{'%:methods'}->{$label};
}));

$::Role->add_method('has_method' => ::make_method(sub {
    my ($self, $label) = @_;
    exists ::opaque_instance_attrs($self)->{'%:methods'}->{$label} ? 1 : 0;
}));

$::Role->add_method('is_method_stub' => ::make_method(sub {
    my ($self, $label) = @_;
    blessed(::opaque_instance_attrs($self)->{'%:methods'}->{$label}) eq 'Perl6::StubMethod';
}));

$::Role->add_method('get_method_list' => ::make_method(sub {
    keys %{::opaque_instance_attrs($::SELF)->{'%:methods'}};
}));

## attributes

$::Role->add_method('add_attribute' => ::make_method(sub {
    my ($self, $label, $attribute) = @_;
    ::opaque_instance_attrs($self)->{'%:attributes'}->{$label} = (
        defined $attribute ?
            $attribute
            :
            ::make_stub_attribute($label));
}));

$::Role->add_method('get_attribute' => ::make_method(sub {
    my ($self, $label) = @_;    
    ::opaque_instance_attrs($self)->{'%:attributes'}->{$label};
}));

$::Role->add_method('has_attribute' => ::make_method(sub {
    my ($self, $label) = @_;    
    exists ::opaque_instance_attrs($self)->{'%:attributes'}->{$label} ? 1 : 0;
}));

$::Role->add_method('is_attribute_stub' => ::make_method(sub {
    my ($self, $label) = @_;    
    blessed(::opaque_instance_attrs($self)->{'%:attributes'}->{$label}) eq 'Perl6::StubAttribute';
}));

$::Role->add_method('get_attribute_list' => ::make_method(sub {
    keys %{::opaque_instance_attrs($::SELF)->{'%:attributes'}};
}));

## subroles

$::Role->add_method('roles' => ::make_method(sub {
    my $self = shift;
    ::opaque_instance_attrs($self)->{'@:roles'} = shift if @_;
    ::opaque_instance_attrs($self)->{'@:roles'};
}));

## introspective methods

$::Role->add_method('does' => ::make_method(sub {
    my ($self, $role_name) = @_;
    return undef unless defined $role_name;
    return 1 if $self->name eq $role_name;
    foreach my $sub_role (@{$self->roles}) {
        return 1 if $sub_role->does($role_name);            
    }
    return 0;
}));

$::Role->add_method('collect_all_roles' => ::make_method(sub {
    my ($self, $seen) = @_;
    $seen ||= {};
    my @roles;
    foreach my $role ($self, @{$self->roles}) {
        unless (exists $seen->{$role->name}) {
            $seen->{$role->name}++;
            push @roles => $role;
            push @roles => $role->collect_all_roles($seen) if scalar @{$role->roles};            
        }
    }
    #warn Data::Dumper::Dumper $seen;
    return @roles;
}));

## composition methods

$::Role->add_method('resolve' => ::make_method(sub {
    # XXX -
    # What if $composite was an optional argument?
    # and then I could pass the class in...
    #    $Foo->resolve($Foo)
    # where a Role would not do that.. however that
    # said, there is little use for a Role to resolve
    # itself, at least not the way we are approaching it
    my $composite;
    $composite = $::Role->new('$:name' => 'Composite<' . (0 + \$composite) . '>');
    my @subroles = $::SELF->collect_all_roles;
    foreach my $role (@subroles) {
        foreach my $method_name ($role->get_method_list) {
            # if we have a conflict, but it is not, or has 
            # not already been stubbed out then ...
            if ($composite->has_method($method_name) &&
                !$composite->is_method_stub($method_name)) {
                # we stub the method for the class to implement
                $composite->add_method($method_name => undef);
            }
            else {
                # no conflicts ... add method
                $composite->add_method($method_name => $role->get_method($method_name));
            }
        }
        foreach my $attr_name ($role->get_attribute_list) {
            # same as for methods, if we have the attribute
            # and it is not already a stub then ...
            if ($composite->has_attribute($attr_name) &&
                !$composite->is_attribute_stub($attr_name)) {
                # we stub it out ...
                $composite->add_attribute($attr_name => undef);
            }
            else {
                # no conflicts ... add attribute
                $composite->add_attribute($attr_name => $role->get_attribute($attr_name));
            }
        }        
    }
    $composite->roles(\@subroles);  
    return $composite;
}));

## NOTE:
## we want to prevent the default version 
## of this from taking over which would make
## things like: FooRole.isa(FooRole) true,
## when they really should not be true
$::Role->add_method('isa' => ::make_method(sub { 
    my ($self, $class_name) = @_;
    return undef unless $class_name;
    return 1 if $class_name eq 'Role';
    return 0;
}));

# TODO ... implement the package interface

$::Role->add_method('FETCH' => ::make_method(sub {
    my $self = shift;
    # ...
}));


$::Role->add_method('STORE' => ::make_method(sub {
    my $self = shift;
    # ...
}));

1;