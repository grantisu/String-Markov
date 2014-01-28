package String::Markov;

our $VERSION = 0.001;

use 5.010;
use Moose;
use namespace::autoclean;

use Unicode::Normalize qw(normalize);
use List::Util qw(sum);

has normalize => (is => 'rw', default => 1);
has null      => (is => 'ro', default => "\0");
has order     => (is => 'ro', isa => 'Int', default => 2);

has ['split_sep','join_sep'] => (
	is => 'rw',
	default => sub { undef }
);

has ['transition_count','row_sum'] => (
	is => 'ro',
	isa => 'HashRef',
	default => sub { {} }
);

around BUILDARGS => sub {
	my ($orig, $class, @arg) = @_;
	my %ahash;

	%ahash = @arg == 1 ? %{$arg[0]} : @arg;

	my $sep = delete $ahash{sep} // '';
	die "ERR: sep argument must be scalar; did you mean to set split_sep instead?" if ref $sep;
	$ahash{split_sep} //= $sep;
	$ahash{join_sep}  //= $sep;

	return $class->$orig(\%ahash);
};

sub split_line {
	my ($self, $sample) = @_;
	if ($self->normalize) {
		$sample = normalize('C', $sample);
	}
	return split($self->split_sep, $sample);
}

sub add_sample {
	my ($self, $sample) = @_;
	my $n     = $self->order;
	my $null  = $self->null;

	my $sref  = ref $sample;
	my @nms = ($null,) x $n;

	if ($sref eq 'ARRAY') {
		push @nms, @$sample;
	} elsif (!$sref) {
		die 'ERR: missing split separator,' if !defined $self->split_sep;
		push @nms, $self->split_line($sample);
	} else {
		die "ERR: bad sample type $sref";
	}

	push @nms, $null;

	my $sep   = $self->join_sep // '';
	my $count = $self->transition_count;
	my $sum   = $self->row_sum;
	for my $i (0 .. ($#nms - $n)) {
		my $cur = join($sep, @nms[$i .. ($i + $n - 1)]);
		my $nxt = $nms[$i + $n];
		++$count->{$cur}{$nxt};
		++$sum->{$cur};
	}

	return $self;
}

sub add_files {
	my ($self, @files) = @_;

	local @ARGV = @files;
	while(my $sample = <>) {
		chomp $sample;
		$self->add_sample($sample);
	}

	return $self;
}

sub next_state {
	my ($self, @cur_state) = @_;
	die "ERR: wrong amount of state" if @cur_state != $self->order;

	my $count = $self->transition_count;
	my $sum   = $self->row_sum;

	my $cur = join($self->join_sep // '', @cur_state);
	my $thresh = $sum->{$cur};
	return undef if !$thresh;

	my $s = 0;
	$thresh *= rand();
	my $prob = $count->{$cur};
	keys %$prob;
	my ($k, $v);
	while ($thresh > $s) {
		($k, $v) = each %$prob;
		$s += $v;
	}
	return $k
}

sub walk_chain {
	my ($self) = @_;

	my $null = $self->null;
	my $n  = $self->order;
	my $sep = $self->join_sep // '';
	my @nm = ($null,) x $n;

	do {
		push @nm, $self->next_state(@nm[-$n .. -1]);
	} while ($nm[-1] ne $null);

	@nm = @nm[$n .. ($#nm-1)];

	return wantarray ?
		@nm :
		defined $self->join_sep ?
			join($sep, @nm) :
			\@nm;

}

__PACKAGE__->meta->make_immutable;

1;

