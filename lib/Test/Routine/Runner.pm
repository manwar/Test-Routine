use strict;
use warnings;
package Test::Routine::Runner;

use Carp qw(confess);
use Class::MOP ();
use Moose::Meta::Class;
use Scalar::Util qw(blessed reftype);
use Test::More ();

use Sub::Exporter::Util qw(curry_method);

use namespace::clean;

use Sub::Exporter -setup => {
  exports => [
    run_tests => \'_curry_tester',
    run_me    => \'_curry_tester',
  ],
  groups  => [ default   => [ qw(run_me run_tests) ] ],
};

our $UPLEVEL = 0;

sub _curry_tester {
  my ($class, $name, $arg) = @_;

  Carp::confess("the $name generator does not accept any arguments")
    if keys %$arg;

  return sub {
    local $UPLEVEL = $UPLEVEL + 1;
    $class->$name(@_);
  };
}

sub run_me {
  my ($class, $desc, $arg) = @_;

  if (@_ == 2 and (reftype $desc // '') eq 'HASH') {
    ($desc, $arg) = (undef, $arg);
  }

  my $caller = caller($UPLEVEL);

  local $UPLEVEL = $UPLEVEL + 1;
  $class->run_tests($desc, $caller, $arg);
}

sub _invocant_for {
  my ($class, $inv, $arg) = @_;

  confess "can't supply object and args for running tests"
    if blessed $inv and $arg;

  $arg //= {};

  return $inv if blessed $inv;

  $inv = [ $inv ] if Params::Util::_CLASS($inv);

  my @bases;
  my @roles;

  for my $item (@$inv) {
    Class::MOP::load_class($item);
    my $target = $item->meta->isa('Moose::Meta::Class') ? \@bases
               : $item->meta->isa('Moose::Meta::Role')  ? \@roles
               : confess "can't run tests for this weird thing: $item";

    push @$target, $item;
  }

  confess "can't build a test class from multiple base classes" if @bases > 1;
  @bases = 'Moose::Object' unless @bases;

  my $new_class = Moose::Meta::Class->create_anon_class(
    superclasses => \@bases,
    cache        => 1,
    (@roles ? (roles => \@roles) : ()),
  );

  $new_class->name->new($arg);
}

sub run_tests {
  my ($class, $desc, $inv, $arg) = @_;

  my @caller = caller($UPLEVEL);

  $desc //= sprintf 'tests from %s, line %s', $caller[1], $caller[2];

  my $thing = $class->_invocant_for($inv, $arg);

  my @tests = grep { $_->isa('Test::Routine::Test') }
              $thing->meta->get_all_methods;

  # As a side note, I wonder whether there is any way to format the code below
  # to not look stupid. -- rjbs, 2010-09-28
  my @ordered_tests = sort {
         $a->_origin->{file} cmp $b->_origin->{file}
      || $a->_origin->{nth}  <=> $a->_origin->{nth}
  } @tests;

  Test::More::subtest($desc, sub {
    for my $test (@ordered_tests) {
      $thing->run_test( $test );
    }
  });
}

1;
