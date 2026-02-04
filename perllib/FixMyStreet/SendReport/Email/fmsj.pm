package FixMyStreet::SendReport::Email::fmsj;

use Moo;

BEGIN { extends 'FixMyStreet::SendReport::Email'; }

# Disable VERP (Variable Envelope Return Path) because the SMTP server
# performs sender verification and rejects emails from addresses that
# don't exist (like fms-report-29-xxx@jonava.lt)
has use_verp => ( is => 'ro', default => 0 );

1;
