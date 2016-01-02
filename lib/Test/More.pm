use v6;

unit package More;

use Test::Hub;

my sub generator() { ... }

multi plan(Int $tests) is export {
	hub.send(Test::Event::Ahead.new(:tests));
}
multi skip_all(Str $reason) is export {
	hub.send(Test::Event::SkipAll.new(:$reason));
}
multi done-testing() is export {
	hub.send(Test::Event::Plan::Done-Any);
}
multi done-testing(Int $tests) is export {
	hub.send(Test::Event::Plan::DoneTests.new(:$tests));
}

our $TODO is export = Str;
my sub todo() {
	return $*TODO // $TODO;
}

sub ok(Mu $value, Str $description) is export {
	my $ok = ?$value;
	hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo)));
	return ?$ok;
}

sub is(Mu $got, Mu $expected, Str $description) is export {
	$got.defined; # Hack to deal with Failures
	my $ok = $got eq $expected;
	hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo), :diag[ :$expected, :$got ]));
	return $ok;
}
sub isnt(Mu $got, Mu $expected, Str $description) is export {
	$got.defined; # Hack to deal with Failures
	my $ok = $got ne $expected;
	hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo), :diag[ :$expected, :$got ]));
	return $ok;
}
sub like(Mu $got, Mu $expected, Str $description) is export {
	$got.defined; # Hack to deal with Failures
	my $ok = $got ~~ $expected;
	hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo), :diag[ :$expected, :$got ]));
	return $ok;
}

sub cmp-ok(Mu $got, Any $op, Mu $expected, Str $description) is export {
	$got.defined; # Hack to deal with Failures
	my $ok;
	use MONKEY-SEE-NO-EVAL;
	if $op ~~ Callable ?? $op !! try EVAL "&infix:<$op>" -> $matcher {
		$ok = $matcher($got, $expected);
		hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo), :diag[ :$expected, :matcher($op), :$got ]));
		return $ok;
	}
	else {
		hub.send(Test::Event::Result.new(:!ok, :description("Could not use '$op' as a comparator in: $description"), :todo(todo)));
		return False;
	}
}

sub is-deeply(Mu $got, Mu $expected, Str $description) is export {
	my $ok = $got eqv $expected;
	hub.send(Test::Event::Result.new(:$ok, :$description, :todo(todo), :diag[ :$expected, :$got ]));
	return $ok;
}


sub pass(Str $description) is export {
	hub.send(Test::Event::Result.new(:ok, :$description, :todo(todo)));
	return True;
}
sub flunk(Str $description) is export {
	hub.send(Test::Event::Result.new(:!ok, :$description, :todo(todo)));
	return False;
}

sub skip(Str $explanation, Int $count = 1) is export {
	for 1 .. $count {
		hub.send(Test::Event::Skip.new(:$explanation));
	}
}

multi subtest(&subtests) is export {
	my $parent = hub;
	my $*test-hub = $parent.subtest;
	my Str $*TODO;
	subtests();
	LEAVE {
		$parent.send($*test-hub.to-test);
	}
}
multi subtest(Str $description, &subtests) is export {
	my $parent = hub;
	my $*test-hub = $parent.subtest($description);
	my Str $*TODO;
	subtests();
	LEAVE {
		$parent.send($*test-hub.to-test);
	}
}

sub diag(Str $content) is export {
	hub.send(Test::Event::Comment.new(:$content));
	return True;
}
