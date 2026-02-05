package FixMyStreet::Cobrand::fmsj;
use parent 'FixMyStreet::Cobrand::Default';

use strict;
use warnings;

use FixMyStreet::Map;

sub country {
    return 'LT';
}

sub front_page_data {
    my ($self, $c) = @_;

    # Coordinate di Jonava
    my $lat = 55.06818;
    my $lon = 24.27485;
    my $zoom = 14;

    # Log per debug
    $c->log->info("front_page_data called for fmsj cobrand");

    # Recupera problemi recenti per i pins
    my @problems = eval {
        $c->model('DB::Problem')->search(
            { state => { -in => ['confirmed', 'fixed', 'fixed - council', 'fixed - user'] } },
            { order_by => { -desc => 'confirmed' }, rows => 50 }
        )->all;
    };
    if ($@) {
        $c->log->error("Error fetching problems: $@");
        @problems = ();
    }

    $c->log->info("Found " . scalar(@problems) . " problems for pins");

    my @pins = map {
        {
            latitude => $_->latitude,
            longitude => $_->longitude,
            colour => $_->is_fixed ? 'green' : 'yellow',
            id => $_->id,
            title => $_->title,
        }
    } @problems;

    # Genera dati mappa
    eval {
        FixMyStreet::Map::display_map($c,
            latitude => $lat,
            longitude => $lon,
            pins => \@pins,
            any_zoom => 1,
        );
    };
    if ($@) {
        $c->log->error("Error generating map: $@");
        return;
    }

    $c->log->info("Map generated, stash map type: " . ($c->stash->{map}{type} || 'undefined'));

    # Override zoom per avere zoom fisso a 14
    my $zoom_offset = $c->stash->{map}{zoomOffset} || 0;
    $c->stash->{map}{zoom} = $zoom - $zoom_offset;
}

sub _fallback_body_sender {
    my ( $self, $body, $category, $contact ) = @_;
    # Use our custom Email sender with VERP disabled
    return { method => 'Email::fmsj', contact => $contact };
}

1;
