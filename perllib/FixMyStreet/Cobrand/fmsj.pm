package FixMyStreet::Cobrand::fmsj;
use parent 'FixMyStreet::Cobrand::Default';

use strict;
use warnings;

sub country {
    return 'LT';
}

sub _fallback_body_sender {
    my ( $self, $body, $category, $contact ) = @_;
    # Use our custom Email sender with VERP disabled
    return { method => 'Email::fmsj', contact => $contact };
}

1;
