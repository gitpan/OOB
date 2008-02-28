package oob;

# be as strict and verbose as possible
use strict;
use warnings;

# version
$oob::VERSION = '0.02';

# modules that we need
use Carp qw( croak );
use Scalar::Util qw( blessed refaddr reftype );

# what we may axport
my %export_ok;
@export_ok{ qw(
  oob_get
  oob_reset
  oob_set
) } = ();

# the actual out-of-bounds data
my %data;

# coderefs of stolen DESTROY methods by class
my $can_identify;
my %stolen = ( __PACKAGE__ => \&DESTROY );

# set DEBUG constant if appropriate
BEGIN {
    my $debug = 0 + ( $ENV{OOB_DEBUG} || 0 );
    eval "sub DEBUG () { $debug }";

    # create oob::dump
    no warnings 'once';
    *dump = sub {
        require Data::Dumper;
        if ( defined wantarray ) {
            return wantarray ? %data : \%data;
        }
        print STDERR Data::Dumper::Dumper( \%data );
    } if $debug;
}    #BEGIN

# enable final debugger if necessary
END {
    if (DEBUG) {
        require Data::Dumper;
        print STDERR "Final state of oob data:\n";
        print STDERR Data::Dumper::Dumper( \%data );
    }
}

# satisfy -require-
1;

#-------------------------------------------------------------------------------
#
# Functional Interface
#
#-------------------------------------------------------------------------------
# oob_get
#
#  IN: 1 reference to value
#      2 key to fetch
#      3 package in which key lives (optional)
# OUT: 1 value or undef

sub oob_get (\[$@%&*]$@) {

    # we're debugging
    if ( DEBUG > 1 ) {
        my $id  = _unique_id( $_[0] );
        my $key = _generate_key( $_[1], $_[2] );
        print STDERR "oob_get with @_: $id -> $key\n";
    }

    # return value without autovivifying
    if ( my $values = $data{ _unique_id( $_[0] ) } ) {
        return $values->{ _generate_key( $_[1], $_[2] ) };
    }

    return;
}    #oob_get

#-------------------------------------------------------------------------------
# oob_reset
#
#  IN: 1 reference to value
#      2 package in which key lives (optional)
# OUT: 1 hash ref with all values

sub oob_reset (\[$@%&*]@) {

    # we're debugging
    if ( DEBUG > 1 ) {
        my $id  = _unique_id( $_[0] );
        print STDERR "oob_reset with @_: $id\n";
    }

    return delete $data{ _unique_id( $_[0] ) };
}    #oob_reset

#-------------------------------------------------------------------------------
# oob_set
#
#  IN: 1 reference to value
#      2 key to set
#      3 value to set
#      4 package in which key lives (optional)
# OUT: 1 any old value

sub oob_set (\[$@%&*]$$@) {

    # scalar specified
    if ( !reftype $_[0] ) {
        bless \$_[0], __PACKAGE__;
    }

    # already blessed and not seen before
    elsif ( my $blessed = blessed $_[0] ) {
        if ( !$stolen{$blessed} ) {

            # didn't try to load Sub::Identify before
            if ( !defined $can_identify ) {

                # cannot perform cleanup on blessed objects
                $can_identify = eval { require Sub::Identify; 1 } || 0;
                die <<'TEXT' if !$can_identify; # maybe warn better?
Cannot perform cleanup on meta-data of blessed objects
because the Sub::Identify module is not installed.
TEXT
            }

            # remember current DESTROY logic and put in our own in there
            if ($can_identify) {
                my $destroy  = $stolen{$blessed} = $blessed->can('DESTROY');
                my $fullname = Sub::Identify::sub_fullname($destroy);
                no strict 'refs';
                *$fullname = sub { $destroy->( $_[0] ); &DESTROY( $_[0] ) };
            }
        }
    }

    # not blessed yet, so bless it now
    else {
        bless $_[0], __PACKAGE__;
    }

    # we're debugging
    if (DEBUG) {
        my $id  = _unique_id( $_[0] );
        my $key = _generate_key( $_[1], $_[3] );
        print STDERR "oob_set with @_: $id -> $key\n";
    }

    # want to know old value
    if ( defined wantarray ) {
        my $id  = _unique_id( $_[0] );
        my $key = _generate_key( $_[1], $_[3] );
        my $old = $data{$id}->{$key};
        $data{$id}->{$key} = $_[2];
        return $old;
    }

    # just set it
    $data{ _unique_id( $_[0] ) }->{ _generate_key( $_[1], $_[3] ) } = $_[2];

    return;
}    #oob_set

#-------------------------------------------------------------------------------
#
# Standard Perl features
#
#-------------------------------------------------------------------------------
# import
#
# Export any constants requested
#
#  IN: 1 class (ignored)
#      2..N constants to be exported

sub import {
    shift;

    # nothing to export
    if (!@_) {
        return;
    }

    # we want all constants
    elsif ( @_ == 1 and $_[0] eq ':all' ) {
        @_ = keys %export_ok;
    }

    # something we don't know how to handle
    elsif ( my @huh = grep { !exists $export_ok{$_} } @_ ) {
        croak "Don't know what to do with: @huh";
    }

    # determine namespace to export to
    my $namespace = caller() . '::';

    # we're debugging
    print STDERR "Exporting @_ to $namespace\n" if DEBUG;

    # export requested constants
    no strict 'refs';
    *{$namespace.$_} = \&$_ foreach @_;

    return;
}    #import

#-------------------------------------------------------------------------------
# AUTOLOAD
#
# Manage auto-creation of missing methods
#
#  IN: 1 class
#      2 key
#      3 value to set

sub AUTOLOAD {

    # attempting to call debug when not debugging
    return if $oob::AUTOLOAD eq 'oob::dump';
    
    # don't know what to do with it
    my $class = shift;
    croak "Undefined subroutine $oob::AUTOLOAD" if !$class->isa(__PACKAGE__);

    # seems to be an attribute we don't know about
    if ( @_ == 2 ) {
        $oob::AUTOLOAD =~ m#::(\w+)$#;
        croak "Attempt to set unregistered oob attribute '$1'";
    }

    # registration
    elsif ( !@_ ) {
        my ( $namespace, $key ) = split '::', $oob::AUTOLOAD;

        # install a method to handle it
        no strict 'refs';
        *$oob::AUTOLOAD = sub {
            return if @_ < 2; # another registration and huh?
            return @_ == 3
             ? oob_set( $_[1], $key => $_[2], $namespace )
             : oob_get( $_[1], $key, $namespace );
        };
    }

    return;
}    #AUTOLOAD

#-------------------------------------------------------------------------------
# DESTROY
#
#  IN: 1 instantiated object

sub DESTROY {

    # we're debugging
    if (DEBUG) {
        my $id  = _unique_id( $_[0] );
        print STDERR "oob::DESTROY with @_: $id\n";
    }

    return delete $data{ _unique_id( $_[0] ) };
}    #DESTROY
    
#-------------------------------------------------------------------------------
#
# Internal methods
#
#-------------------------------------------------------------------------------
# _generate_key
#
# Return the key of the given parameters
#
#  IN: 1 basic key value
#      2 any package specification (default: 2 levels up)
# OUT: 1 key to be used in internal hash

sub _generate_key {

    # fetch the namespace
    my $namespace = defined $_[1]
      ? ( "$_[1]" ? "$_[1]--" : '' )
      : ( caller(1) )[0] . '--';

    return $namespace . $_[0];
}    #_generate_key

#-------------------------------------------------------------------------------
# _unique_id
#
# Return the key of the given parameters
#
#  IN: 1 reference to value to work with
# OUT: 1 id to be used in internal hash

sub _unique_id {

    # no ref, make it!
    my $reftype = reftype $_[0];
    if ( !$reftype ) {
        return refaddr \$_[0];
    }

    # special handling for refs to refs
    elsif ( $reftype eq 'REF' ) {
        my $ref = ${$_[0]};
        $ref = ${$ref} while reftype $ref eq 'REF';
        return refaddr $ref;
    }

    # just use the refaddr
    return refaddr $_[0];
}    #_unique_id


#-------------------------------------------------------------------------------

__END__

=head1 NAME

oob - out of bounds data for any data structure in Perl

=head1 VERSION

This documentation describes version 0.02.

=head1 SYNOPSIS

 # object oriented interface
 use oob;

 # register attributes
 oob->ContentType;
 oob->EpochStart;
 oob->Currency;
 oob->Accept;

 # scalars (or scalar refs)
 oob->ContentType( $message, 'text/html' );
 my $type = oob->ContentType($message);
 print <<"MAIL";
 Content-Type: $type

 $message
 MAIL

 # arrays
 oob->EpochStart( \@years, 1970 );
 my $offset = oob->EpochStart( \@years );
 print $offset + $_ , $/ foreach @years;

 # hashes
 oob->Currency( \%salary, 'EUR' );
 my $currency = oob->Currency( \%salary );
 print "$_: $salary{$_} $currency\n" foreach sort keys %salary;

 # subroutines
 oob->Accept( \&frobnicate, \@classes );
 my $classes = oob->Accept( \&frobnicate );

 # functional interface
 use oob qw( oob_set oob_get oob_reset );

 package Foo;
 oob_set( $scalar, key => $value );
 my $value = oob_get( @array, 'key' );
 oob_reset( %hash );

 package Bar;
 my $value = oob_get( $arrayref, 'key', 'Foo' ); # other module's namespace

=head1 DESCRIPTION

This module makes it possible to assign any out of bounds data (attributes)
to any Perl data structure with both a functional and an object oriented
interface.  Out of bounds data is basically represented by a key / value pair.

=head2 Object Oriented Interface

The object oriented interface allows you to easily define globally accessible
meta-data attributes.  To prevent problems by poorly typed attribute names,
you need to register a new attribute at least once before being able to set
it.  Attempting to access any non-existing meta-data attributes will B<not>
result in an error, but simply return undef.

Registration of an attribute is simple: just calling it as a class method on
the C<oob> module is enough:

 use oob;
 oob->ContentType;

After that, you can use that attribute on any Perl data structure:

 oob->ContentType( $string,  'text/html' ); # scalars don't need to be ref'ed
 oob->ContentType( \$string, 'text/html' ); # same as above
 oob->ContentType( \@array,  'text/html' );
 oob->ContentType( \%hash,   'text/html' );
 oob->ContentType( \&sub,    'text/html' );
 oob->ContentType( *FILE,    'text/html' ); # globs
 oob->ContentType( $handle,  'text/html' ); # blessed objects

=head2 Functional Interface

The functional interface gives more flexibility but may not be as easy to
type.  It basically allows you to specify arrays, hashes and subs directly
(courtesy of Perl's prototyping feature).  The functional interface is in
principle limited to the namespace from which it is being called, but can
be overridden if necessary.

 use oob qw( oob_set oob_get oob_reset ); # nothing exported by default

 package Foo;
 oob_set( $string, ContentType => 'html' );
 my $type = oob_get( $string, 'ContentType' );        # attribute in 'Foo'

 package Bar;
 my $type = oob_get( $string, ContentType => 'Foo' ); # other namespace
 oob_set( $string, ContentType => "text/$type" );     # attribute in "Bar"

 oob_set( $string, ContentType => 'text/html' ); # equivalent to object
 oob_set( @array,  ContentType => 'text/html' ); # oriented examples, but
 oob_set( %hash,   ContentType => 'text/html' ); # limited to the current
 oob_set( &sub,    ContentType => 'text/html' ); # namespace
 oob_set( *FILE,   ContentType => 'text/html' );
 oob_set( $handle, ContentType => 'text/html' );

=head1 THEORY OF OPERATION

The functional interface of the C<oob> pragma basically uses the C<refaddr>
of the given value as an internal key to create an "inside-out" hash ref with
the given keys and values.  If the value is not blessed yet, it will be
blessed in the C<oob> class, so that it can perform cleanup operations once
the value goes out of scope.

If a blessed value is specified, the DESTROY method of the class of the
object is stolen, so that C<oob> can perform its cleanup after the original
DESTROY method was called.  This is only supported if the L<Sub::Identify>
module is also installed.  If that module cannot be found, a warning will
be issued once to indicate that no cleanup can be performed for blessed
objects, and execution will then continue as normal.

To prevent clashes between different modules use of the out-of-bounds data,
the package name of the caller is automatically added to any key specified,
thereby giving each package its own namespace in the C<oob> environment.
However, if need be, a module can access data from another package by the
additional specification of its namespace.

The object oriented interface is really nothing more than synctactic sugar
on top of the functional interface.  The namespace that is being used by all
of the attributes specified with the object oriented interface is the C<oob>
package itself.

=head1 REQUIRED MODULES

 Scalar::Util (1.14)

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 ACKNOWLEDGEMENTS

Juerd Waalboer for the insight that you don't need to keep a reference on
a blessed Perl data structure such as a scalar, array or hash, but instead
can use B<any> reference to that data structure to find out its blessedness.

=head1 COPYRIGHT

Copyright (c) 2008 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
