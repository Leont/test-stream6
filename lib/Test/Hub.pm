use v6;

unit module Test;

role Event {
}

role Event::Terminate does Event {
	method exit-code(-->Int) { ... }
}
role Event::Plan does Event {
}

role Event::Plan::Tests does Event::Plan {
	has Int:D $.tests is required;
}
role Event::Plan::Front does Event::Plan {
}
role Event::Plan::Tail does Event::Plan {
}

class Event::Plan::Ahead does Event::Plan::Tests does Event::Plan::Front {
}
class Event::Plan::Done-Any does Event::Plan::Tail {
}
class Event::Plan::DoneTests does Event::Plan::Tests does Event::Plan::Tail {
}
class Event::Plan::Skip-All does Event::Plan::Front does Event::Plan::Tail does Event::Terminate {
	has Str:D $.explanation is required;
	method exit-code(--> Int) { 0 }
}

role Event::Case does Event {
	method pass(--> Bool) { ... }
}

role Event::Test does Event::Case {
	has Str $.description;
	has Str $.todo;
	method ok(--> Bool) { ... }
	method pass(--> Bool) {
		return $.ok || $.todo.defined;
	}
}

class Event::Result does Event::Test {
	has Bool:D $.ok is required;
}

class Event::SubTest does Event::Test {
	has Event::Test @.tests;
	method ok(--> Bool) {
		return ?all(@!tests».pass);
	}
}

class Event::Skip does Event::Case {
	method pass(--> Bool) { return True }
	has Str:D $.explanation is required;
}

class Event::Comment does Event {
	has Str:D $.content is required;
	has Bool:D $.out-of-band = False;
}

class Event::Bail-Out does Event::Terminate {
	has Str:D $.reason is required;
	method exit-code(--> Int) { 255 }
}

class State {
	has Int:D $.count = 0;
	has Int:D $.failed = 0;
	has Int:D $.seen = 0;
	has Int $.planned;
	has Bool $!finished = False;

	proto method update(Event:D $event) { * }
	multi method update(Event $event) {
	}
	multi method update(Event::Test $test) {
		$!seen++;
		$!failed++ if not $test.pass;
	}
	multi method update(Event::Plan $plan) {
		if $!planned.defined {
			die "Can't plan twice";
		}
		if $plan ~~ Event::Plan::Ahead {
			die "Can't plan ahead once " if $!seen != 0;
		}
		if $plan ~~ Event::Plan::Tail {
			$!finished = True;
		}
		given $plan {
			when Event::Plan::Tests {
				$!planned = $plan.tests;
			}
			default {
				$!planned = $!seen;
			}
		}
	}
	method finishing() {
		return ();
	}
	method exit-code() {
		return min($!failed, 254) if $!failed > 0;
		return 255 if not $!planned.defined;
		return min(abs($!planned - $!seen), 254);
	}
}

role Formatter {
	proto method write(Event:D $event) { * }
	method finish() { }
}

class Formatter::TAP does Formatter {
	has IO::Handle $.out = $*OUT;
	has IO::Handle $.err = $*ERR;
	has Int $!seen = 0;
	has Int $!counter = 0;
	#submethod BUILDALL() {
	#}

	multi method write(Event $event) {
		$!out.say($_) for $.format($event);
	}
	multi method format(Event::Plan::Tests $plan) {
		return '1..' ~ $plan.tests;
	}
	multi method format(Event::Plan::Done-Any $plan) {
		return '1..' ~ $!seen;
	}
	multi method format(Event::Plan::Skip-All $plan) {
		return '1..0 # ' ~ $plan.explanation;
	}
	my %replacement = (
		'\\' => '\\\\',
		'#'  => '\\#',
		"\n" => '\\n',
	);
	method format-test(Event::Test $test) {
		my $ok = $test.ok ?? 'ok' !! 'not ok';
		my $description = $test.description.subst(/<[\\\#\n]>/, { %replacement{$_} }, :g);
		my $line = ($ok, ++$!counter, '-', $description).join(' ');
		$line ~= ' # todo ' ~ $test.todo if $test.todo.defined;
		return $line;
	}
	multi method format(Event::Test $test) {
		return $.format-test($test);
	}
	multi method format(Event::SubTest $test) {
		my @return = $test.tests.map($.format($_)).map(*.indent(4));
		@return.push: $.format-test($test);
		return @return;
	}
	multi method format(Event::Skip $skip) {
		return 'ok ' ~ ++$!counter ~ ' # skip ' ~ $skip.explanation;
	}
	multi method format(Event::Comment $comment) {
		my @lines = $comment.content.split(/\n/);
		my $fh = $comment.out-of-band ?? $!err !! $!out;
		return @lines.map("# " ~ *);
	}
}

class Terminate {
	has Event $.reason;
}

class Hub::SubTest { ... }

role Hub {
	has State $!state .= new;
	has @!filters;
	submethod BUILD(:@!filters) { }
	method add_filter(&callback, *%arguments) {
		push @!filters, %( :&callback, %arguments );
		return;
	}
	method send(Event $event is copy) {
		for @!filters -> % (:&callback, *%arguments) {
			return without $event = self.&callback($event);
		}
		my $next = $!state.update($event);
		$.write($event);
		if $event ~~ Event::Terminate {
			...;
		}
		return;
	}

	method write(Event $e) { ... }
	method terminate(Int:D ) { ... }
	method subtest(Str $description --> Hub) {
		return Hub::SubTest.new(:$description, :@!filters);
	}
	method finish() {
		self.send($_) for $!state.finishing;
		self.terminate($!state.exit-code);
	}
}

class Hub::SubTest does Hub {
	has $.description;
	has @!tests;
	method write(Event $e) { ... }
	method to-test(--> Event::SubTest) {
		Event::SubTest.new(:$!description, :@!tests);
	}
	method terminate(Int:D ) {
	}
}

class Hub::Main does Hub {
	has Formatter:D $.formatter is required;
	submethod BUILD(:$!formatter) {}
	method write(Event $e) {
		$!formatter.write($e);
	}
	method terminate(Int:D $code) {
		exit $code;
	}
}

sub hub() is export {
	state $hub;
	return $*test-hub // $hub //= Hub::Main.new(:formatter(Formatter::TAP.new));
}

END {
	hub.finish;
}
