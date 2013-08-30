# --8<--8<--8<--8<--
#
# Copyright (C) 1998-2011 Smithsonian Astrophysical Observatory
#
# This file is part of Config-Wild
#
# Config-Wild is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -->8-->8-->8-->8--

package Config::Wild;

use strict;
use warnings;

use Carp qw( carp croak );
use FileHandle;
use Cwd qw[ getcwd ];

our $VERSION = '1.5';


sub new {
    my $this = shift;
    my $class = ref( $this ) || $this;

    my $attr = ref $_[-1] eq 'HASH' ? pop @_ : {};

    my $self = {
        wild => [],    # regular expression keywords
        abs  => {},    # absolute keywords
        attr => {
            UNDEF      => undef,    # function to call from value when
                                    # keyword not defined
            PrintError => 0,        # warn() on error
            dir        => '.',
            %$attr,
        },

    };

    bless $self, $class;

    my $file = shift;

    if ( $file ) {
        $self->load( $file ) or return undef;
    }

    $self;
}

sub load {
    my ( $self, $file ) = @_;
    my ( $keyword, $value );

    unless ( $file ) {
        $self->_errmsg( 'load: no file specified' );
        return undef;
    }

    my %files = ();
    my @files = ( { file => $file, pos => 0 } );

    my $cwd = getcwd;
    chdir( $self->{attr}{dir} ) or do {
        $self->_errmsg(
            "load: couldn't change directory to $self->{attr}{dir}" );
        return undef;
    };

    my $ret = eval {

      loop:
        while ( @files ) {
            my $file = $files[0]->{file};
            my $pos  = $files[0]->{pos};

            # if EOF on last file, don't bother with it
            next if $files[0]->{pos} == -1;

            my $fh = new FileHandle $file or do {
                $self->_errmsg( "load: error opening file `$file'" );
                return;
            };

            seek( $fh, $files[0]->{pos}, 0 );

            # loop through file
            my $line = 0;
            while ( <$fh> ) {
                $files[0]->{pos} = tell;
                $line++;

                # ignore comment lines or empty lines
                next if /^\s*\#|^\s*$/;

                chomp;

                if ( /^\s*%include\s+(.*)/ ) {
                    if ( CORE::exists $files{$1} ) {
                        $self->_errmsg(
                            "load: infinite loop trying to read $1" );
                        return undef;
                    }
                    $files{$1}++;
                    unshift @files, { file => $1, pos => 0 };
                    $fh->close;
                    redo loop;
                }

                $self->_parsepair( $_ ) or do {
                    $self->_errmsg( "load: $file: can't parse line $line" );
                    return;
                  }

            }

        }
        continue {
            shift @files;
        }


        return 1;
    };

    chdir( $cwd ) or do {
        $self->_errmsg( "load: error restoring directory to $cwd" );
        return undef;
    };


    return $ret;
}

sub load_cmd {
    my ( $self, $argv, $attr ) = @_;
    my $keyword;

    $attr = {} unless defined $attr;

    foreach ( @$argv ) {
        if (   $$attr{Exists}
            && ( $keyword = ( $self->_splitpair( $_ ) )[0] )
            && !$self->_exists( $keyword ) )
        {
            $self->_errmsg( "load_cmd: keyword `$keyword' doesn't exist" );
            return undef;
        }

        $self->_parsepair( $_ ) or do {
            $self->_errmsg( "load_cmd: can't parse line $_" );
            return undef;
          }
    }

    1;
}


sub set {
    my ( $self, $keyword, $value ) = @_;

    die unless defined( $keyword ) and defined( $value );
    # so, is it a regular expression or not?
    if ( $keyword =~ /\{/ ) {
        # quote all characters outside of curly brackets.
        $keyword = join(
            '',
            map {
                substr( $_, 0, 1 ) ne '{'
                  ? quotemeta( $_ )
                  : substr( $_, 1, -1 )
            } $keyword =~ /( [^{}]+ | {[^\}]*} )/gx
        );

        unshift @{ $self->{wild} }, [ $keyword, $value ];
    }
    else {
        $self->{abs}->{$keyword} = $value;
    }
}

# for backwards compatibility
sub value {
    goto &get;
}

sub get {
    my ( $self, $keyword ) = @_;

    unless ( $keyword ) {
        $self->_errmsg( 'value: no keyword specified' );
        return undef;
    }

    return $self->_expand( $self->{abs}->{$keyword} )
      if CORE::exists( $self->{abs}->{$keyword} );

    foreach ( @{ $self->{wild} } ) {
        return $self->_expand( $_->[1] ) if $keyword =~ /$_->[0]/;
    }

    return $self->{attr}{UNDEF}->( $keyword )
      if defined $self->{attr}{UNDEF};

    undef;
}

sub getbool {

    require Lingua::Boolean::Tiny;

    my $self = shift;

    return Lingua::Boolean::Tiny::boolean( $self->get( @_ ) );
}

sub delete {
    my ( $self, $keyword ) = @_;

    unless ( $keyword ) {
        $self->_errmsg( 'delete: no keyword specified' );
        return undef;
    }

    if ( CORE::exists $self->{abs}->{$keyword} ) {
        delete $self->{abs}->{$keyword};
    }
    else {
        $self->{wild} = grep( $_->[0] ne $keyword, @{ $self->{wild} } );
    }
    1;
}

sub exists {
    my ( $self, $keyword ) = @_;

    unless ( $keyword ) {
        $self->_errmsg( 'exists: no keyword specified' );
        return undef;
    }

    return $self->_exists( $keyword );
}

sub _exists {
    my ( $self, $keyword ) = @_;

    return 1 if CORE::exists( $self->{abs}->{$keyword} );

    foreach ( @{ $self->{wild} } ) {
        return 1 if $keyword =~ /$_->[0]/;
    }

    undef;

}


sub set_attr {
    my ( $self, $attr ) = @_;
    my ( $key, $value );

    while ( ( $key, $value ) = each %{$attr} ) {
        unless ( CORE::exists $self->{attr}{$key} ) {
            $self->_errmsg( "set_attr: unknown attribute: `$key'" );
            return undef;
        }
        $self->{attr}{$key} = $value;
    }

}



sub errmsg {
    my $self = shift;
    return $self->{errmsg};
}

sub _errmsg {
    my ( $self, $errmsg ) = @_;

    $self->{errmsg} = __PACKAGE__ . ': ' . $errmsg;
    if ( $self->{attr}{PrintError} ) {
        if ( ref( $self->{attr}{PrintError} ) eq 'CODE' ) {
            $self->{attr}{PrintError}->( $errmsg );
        }
        else {
            warn $errmsg, "\n";
        }
    }
}


#========================================================================
#
# AUTOLOAD
#
# Autoload function called whenever an unresolved object method is
# called.  If the method name relates to a defined VARIABLE, we patch
# in $self->get() and $self->set() to magically update the varaiable
# (if a parameter is supplied) and return the previous value.
#
# Thus the function can be used in the folowing ways:
#    $cfg->variable(123);     # set a new value
#    $foo = $cfg->variable(); # get the current value
#
# Returns the current value of the variable, taken before any new value
# is set.  Prints a warning if the variable isn't defined (i.e. doesn't
# exist rather than exists with an undef value) and returns undef.
#
#========================================================================

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my $keyword;
    my ( $oldval, $newval );


    # splat the leading package name
    ( $keyword = $AUTOLOAD ) =~ s/.*:://;

    # ignore destructor
    $keyword eq 'DESTROY' && return;

    if ( CORE::exists( $self->{abs}->{$keyword} ) ) {
        $oldval = $self->_expand( $self->{abs}->{$keyword} );
    }
    else {
        my $found = 0;
        foreach ( @{ $self->{wild} } ) {
            $oldval = $self->_expand( $_->[1] ), $found++, last
              if $keyword =~ /$_->[0]/;
        }
        if ( !$found ) {
            return $self->{attr}{UNDEF}->( $keyword )
              if defined( $self->{attr}{UNDEF} );

            $self->{errmsg} = __PACKAGE__ . ": $keyword doesn't exist";
            return undef;
        }
    }

    # set a new value if a parameter was supplied
    $self->set( $keyword, $newval )
      if defined( $newval = shift );

    # return old value
    return $oldval;
}

sub _expand {
    my ( $self, $value ) = @_;

    my $stop = 0;
    until ( $stop ) {
        $stop = 1;

        # expand ${VAR} as environment variables
        $value =~ s/\$\{(\w+)\}/defined $ENV{$1} ? $ENV{$1} : ''/ge
          and $stop = 0;

        # expand $(VAR) as a ConfigWild variable
        $value =~ s{\$\((\w+)\)} {
	    defined $self->{abs}->{$1} ? $self->{abs}->{$1} : '';
	}gex
          and $stop = 0;

        # expand any unparenthesised/braced variables,
        # e.g. "$var", as ConfigWild vars or environment variables.
        # leave untouched if not
        $value =~ s{\$(\w+)} {
	    defined $self->{abs}->{$1} ? $self->{abs}->{$1} :
	      defined $ENV{$1} ? $ENV{$1} :
		"\$$1"
	    }gex
          and $stop = 0;
    }
    # return the value
    $value;
}

sub _splitpair {
    my ( $self, $pair ) = @_;
    my ( $keyword, $value );

    $pair =~ s/^\s+//;
    $pair =~ s/\s+$//;

    return 2 != ( ( $keyword, $value ) = $pair =~ /([^=\s]*)\s*=\s*(.*)/ )
      ? ()
      : ( $keyword, $value );
}

sub _parsepair {
    my ( $self, $pair ) = @_;

    my ( $keyword, $value );

    $pair =~ s/^\s+//;
    $pair =~ s/\s+$//;

    return undef
      if 2 != ( ( $keyword, $value ) = $pair =~ /([^=\s]*)\s*=\s*(.*)/ );

    $self->set( $keyword, $value );
    1;
}


1;
__END__


=head1 NAME

Config::Wild - parse an application configuration file with wildcard keywords

=head1 SYNOPSIS

  use Config::Wild;
  $cfg = Config::Wild->new();
  $cfg = Config::Wild->new( $configfile, \%attr );

=head1 DESCRIPTION

This is a simple package to parse and present to an application
configuration information read from a configuration file.
Configuration information in the file has the form

  keyword = value

where I<keyword> is a token which may contain Perl regular expressions
surrounded by curly brackets, i.e.

  foobar.{\d+}.name = goo

and I<value> is the remainder of the line after any whitespace following
the C<=> character is removed.

Keywords which contain regular expressions are termed I<wildcard>
keywords; those without are called I<absolute> keywords.  Wildcard
keywords serve as templates to allow grouping of keywords which have
the same value.  For instance, say you've got a set of keywords which
normally have the same value, but where on occaision you'd like to
override the default:

  p.{\d+}.foo = goo
  p.99.foo = flabber

I<value> may reference environmental variables or other B<Config::Wild>
variables via the following expressions:

=over 4

=item *

Environment variables may be accessed via C<${var}>:

  foo = ${HOME}/foo

If the variable doesn't exist, the expression is replaced with
an empty string.


=item *

Other B<Config::Wild> variables may be accessed via C<$(var)>.

  root = ${HOME}
  foo = $(root)/foo

If the variable doesn't exist, the expression is replaced with
an empty string.  Variable expansions can be nested, as in

  root = /root
  branch = $(root)/branch
  tree = $(branch)/tree

C<tree> will evaluate to C</root/branch/tree>.

=item *

I<Either> type of variable may be accessed via C<$var>.
In this case, if I<var> is not a B<Config::Wild> variable, it is
assumed to be an environmental variable.
If the variable doesn't exist, the expression is left as is.

=back

Substitutions are made when the B<value> method is called, not when
the values are first read in.

Lines which begin with the C<#> character are ignored.  There is also a
set of directives which alter the where and how B<Config::Wild> reads
configuration information.  Each directive begins with the C<%> character
and appears alone on a line in the config file:

=over 4

=item B<%include file>

Temporarily interrupt parsing of the current input file, and switch
the input stream to the specified I<file>.

=back

=head1 METHODS

=over 4

=item B<new>

  $cfg = Config::Wild->new( \%attr );
  $cfg = Config::Wild->new( $config_file, \%attr );

Create a new B<Config::Wild> object, optionally loading configuration
information from a file.  It returns the new object, or C<undef> upon
error.

Additional attributes which modify the behavior of the object may be
specified in the passed C<%attr> hash. They may also be specifed or modified after
object creation using the C<set_attr> method.

The following attributes are available:

=over

=item C<UNDEF> = function

This defines a function to be called when the value of an undefined
keyword is requested.  The function is passed the name of the keyword.
It should return a value, which will be returned as the value of the
keyword.

For example,

  $cfg = Config::Wild->new( "foo.cnf", { UNDEF => \&undefined_keyword } );

  sub undefined_keyword
  {
    my $keyword = shift;
    return 33;
  }

You may also use this to centralize error messages:

  sub undefined_keyword
  {
    my $keyword = shift;
    die("undefined keyword requested: $keyword\n");
  }

To reset this to the default behavior, set C<UNDEF> to C<undef>:

  $cfg->set_attr( UNDEF => undef );


=item C<PrintError> = boolean

If true, all errors will result in a call to B<warn()>.  If it is set
to a reference to a function, that function will be called instead.

=item C<dir> = directory

If specified the current working directory will be changed to the
specified directory before a configuration file is loaded.

=back

=item B<load>

  $cfg->load( $file );

Load information from a configuration file into the current object.
New configuration values will supersede previous ones, in the
following complicated fashion.  Absolutely specified keywords will
overwrite previously absolutely specified values.  Since it is
difficult to determine whether the set of keywords matched by two
regular expressions overlap, wildcard keywords are pushed onto a
last-in first-out (LIFO) list, so that when the application requests a
value, it will use search the wildcard keywords in reverse order that
they were specified.

It returns 1 upon success, C<undef> if an error ocurred.  The error
message may be retrieved with the B<errmsg> method.


=item B<load_cmd>

  $cfg->load_cmd( \@ARGV );
  $cfg->load_cmd( \@ARGV,\%attr );

Parse an array of keyword-value pairs (possibly command line
arguments), and insert them into the list of keywords.  It can take an
optional hash of attributes with the following values:

=over 8

=item C<Exists>

If true, the keywords must already exist. An error will be returned if
the keyword isn't in the absolute list, or doesn't match against the
wildcards.

=back

Upon success, it returns 1, upon error it returns C<undef> and sets
the object's error message (see B<errmsg()>).

For example,

  $cfg->load_cmd( \@ARGV, { Exists => 1} )
    || die( $cfg->errmsg, "\n" );

=item B<set>

  $cfg->set( $keyword, $value );

Explicitly set a keyword to a value.  Useful to specify keywords that
should be available before parsing the configuration file.

=item B<get>

  $value = $cfg->get( $keyword );

Return the value associated with a given keyword.  B<$keyword> is
first matched against the absolute keywords, then agains the
wildcards.  If no match is made, C<undef> is returned.

=item B<getbool>

  $value = $cfg->getbool( $keyword );

Convert the value associated with a given keyword to a true or false
value using B<L<Lingua::Boolean::Tiny>>.  B<$keyword> is first matched against the absolute keywords,
then agains the wildcards.  If no match is made, or the value could
not be converted to a truth value, C<undef> is returned.


=item B<delete>

  $cfg->delete( $keyword );

Delete C<$keyword> from the list of keywords (either absolute or wild)
stored in the object.  The keyword must be an exact match.  It is not
an error to delete a keyword which doesn't exist.


=item B<exists>

  $exists = $cfg->exists( $keyword );

Returns non-zero if the given keyword matches against the list of
keywords in the object, C<undef> if not.


=item B<set_attr>

  $cfg->set_attr( \%attr );

Set internal configuration parameters.  It returns C<undef> and sets
the object's error message upon error.  The available parameters are:


=item B<errmsg>

Returns the last error message stored in the object;

=back

There are also "hidden" methods which allow more natural access to
keywords.  You may access a keyword's value by specifying the keyword
as the method, instead of using B<value>.  The following are
equivalent:

   $foo = $cfg->get( 'keyword' );
   $foo = $cfg->keyword;

If C<keyword> doesn't exist, it returns C<undef>.

Similarly, you can set a keyword's value using a similar syntax.  The
following are equivalent, if the keyword already exists:

   $cfg->set( 'keyword', $value );
   $cfg->keyword( $value );

If the keyword doesn't exist, the second statement does nothing.

It is a bit more time consuming to use these methods rather than using
B<set> and B<value>.

=head1 COPYRIGHT & LICENSE

Copyright 1998-2011 Smithsonian Astrophysical Observatory

This software is released under the GNU General Public License.  You
may find a copy at

   http://www.fsf.org/copyleft/gpl.html


=head1 SEE ALSO

B<AppConfig>, an early version of which was the inspiration for this
module.


=head1 AUTHOR

Diab Jerius, E<lt>djerius@cpan.orgE<gt>
