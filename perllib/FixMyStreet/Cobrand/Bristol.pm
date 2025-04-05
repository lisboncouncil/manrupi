=head1 NAME

FixMyStreet::Cobrand::Bristol - code specific to the Bristol cobrand

=head1 SYNOPSIS

Bristol is a unitary authority, with its own Open311 server.

=head1 DESCRIPTION

=cut

package FixMyStreet::Cobrand::Bristol;
use parent 'FixMyStreet::Cobrand::Whitelabel';

use Moo;
with 'FixMyStreet::Roles::Open311Alloy';
with 'FixMyStreet::Roles::Open311Multi';

use strict;
use warnings;

=head2 Defaults

=over 4

=cut

sub council_area_id {
    [
        2561,  # Bristol City Council
        2642,  # North Somerset Council
        2608,  # South Gloucestershire Council
    ]
}
sub council_area { return 'Bristol'; }
sub council_name { return 'Bristol City Council'; }
sub council_url { return 'bristol'; }

=item * Bristol use the OS Maps API at all zoom levels.

=cut

sub map_type { 'OS::API' }

=item * Users with a bristol.gov.uk email can always be found in the admin.

=cut

sub admin_user_domain { 'bristol.gov.uk' }

=item * Bristol uses the OSM geocoder

=cut

sub get_geocoder { 'OSM' }

=item * We do not send questionnaires.

=back

=cut

sub send_questionnaires { 0 }

sub disambiguate_location {
    my $self    = shift;
    my $string  = shift;

    my $town = 'Bristol';

    return {
        %{ $self->SUPER::disambiguate_location() },
        town   => $town,
        centre => '51.4526044866206,-2.7706173308649',
        span   => '0.202810508012753,0.60740886659825',
        bounds => [ 51.3415749466466, -3.11785543094126, 51.5443854546593, -2.51044656434301 ],
    };
}

=head2 pin_colour

Bristol uses the following pin colours:

=over 4

=item * grey: closed

=item * green: fixed

=item * yellow: newly open

=item * orange: any other open state

=back

=cut

sub pin_colour {
    my ( $self, $p, $context ) = @_;
    return 'grey-cross' if $p->is_closed;
    return 'green-tick' if $p->is_fixed;
    return 'yellow-cone' if $p->state eq 'confirmed';
    return 'orange-work'; # all the other `open_states` like "in progress"
}

sub path_to_pin_icons { '/i/pins/whole-shadow-cone-spot/' }

use constant ROADWORKS_CATEGORY => 'Inactive roadworks';

=head2 categories_restriction

Categories covering the Bristol area have a mixture of Open311 and Email send
methods. Bristol only want Open311 categories to be visible on their cobrand,
not the email categories from FMS.com. We've set up the Email categories with a
devolved send_method, so can identify Open311 categories as those which have a
blank send_method. Also National Highways categories have a blank send_method.
Additionally the special roadworks category should be shown.

=cut

sub categories_restriction {
    my ($self, $rs) = @_;
    return $rs->search( { -or => [
        'me.category' => ROADWORKS_CATEGORY, # Special new category
        'me.send_method' => undef, # Open311 categories
        'me.send_method' => '', # Open311 categories that have been edited in the admin
    ] } );
}


sub dashboard_export_problems_add_columns {
    my ($self, $csv) = @_;

    $csv->add_csv_columns(
        (
            staff_role => 'Staff Role',
        )
    );

    return if $csv->dbi; # All covered already

    my $user_lookup = $self->csv_staff_users;
    my $userroles = $self->csv_staff_roles($user_lookup);

    $csv->csv_extra_data(sub {
        my $report = shift;

        my $by = $csv->_extra_metadata($report, 'contributed_by');
        my $staff_role = '';
        if ($by) {
            $staff_role = join(',', @{$userroles->{$by} || []});
        }
        return {
            staff_role => $staff_role,
        };
    });
}


=head2 open311_config

Bristol's original endpoint requires an email address, so flag to always send one (with
a fallback if one not provided).

=cut

sub open311_config {
    my ($self, $row, $h, $params, $contact) = @_;

    $params->{always_send_email} = 1;
    $params->{multi_photos} = 1;
    $params->{upload_files} = 1;
    $params->{upload_files_for_updates} = 1;
}

sub open311_config_updates {
    my ($self, $params) = @_;
    $params->{multi_photos} = 1;
}

=head2 open311_update_missing_data

All reports sent to Alloy should have a USRN set so the street parent
can be found and the locality can be looked up as well.

The USRN may be set by the roads asset layer, but staff can report anywhere
so are not restricted to the road layer and anyone can be make reports on
specific Bristol owned properties that don't have a USRN

=cut

sub lookup_site_code_config {
    my $host = FixMyStreet->config('STAGING_SITE') ? "tilma.staging.mysociety.org" : "tilma.mysociety.org";
    return {
        buffer => 200, # metres
        url => "https://$host/proxy/bristol/wfs/",
        typename => "COD_LSG",
        property => "USRN",
        version => '2.0.0',
        srsname => "urn:ogc:def:crs:EPSG::27700",
        accept_feature => sub { 1 },
        reversed_coordinates => 1,
    };
}

sub open311_update_missing_data {
    my ($self, $row, $h, $contact) = @_;

    if ($contact->email =~ /^Alloy-/ && !$row->get_extra_field_value('usrn')) {
        if (my $usrn = $self->lookup_site_code($row)) {
            $row->update_extra_field({ name => 'usrn', value => $usrn });
        }
    };
}

=head2 open311_contact_meta_override

We need to mark some of the attributes returned by Bristol's Open311 server
as hidden or server_set.

=cut

sub open311_contact_meta_override {
    my ($self, $service, $contact, $meta) = @_;

    my %server_set = (easting => 1, northing => 1);
    my %hidden_field = (usrn => 1, asset_id => 1);
    foreach (@$meta) {
        $_->{automated} = 'server_set' if $server_set{$_->{code}};
        $_->{automated} = 'hidden_field' if $hidden_field{$_->{code}};
    }
}

sub open311_post_send {
    my ($self, $row, $h) = @_;

    # Check Open311 was successful
    return unless $row->external_id;
    return if $row->get_extra_metadata('extra_email_sent');

    # For Flytipping with witness, send an email also
    my $witness = $row->get_extra_field_value('Witness') || 0;
    return unless $witness;

    my $emails = $self->feature('open311_email') or return;
    my $dest = $emails->{$row->category} or return;
    $dest = [ $dest, 'FixMyStreet' ];

    $row->push_extra_fields({ name => 'fixmystreet_id', description => 'FMS reference', value => $row->id });

    my $sender = FixMyStreet::SendReport::Email->new(
        use_verp => 0, use_replyto => 1, to => [ $dest ] );
    $sender->send($row, $h);
    if ($sender->success) {
        $row->set_extra_metadata(extra_email_sent => 1);
    }

    $row->remove_extra_field('fixmystreet_id');
}

=head2 post_report_sent

Bristol have a special Inactive roadworks category; any reports made in that
category are automatically closed, with an update with explanatory text added.

=cut

sub post_report_sent {
    my ($self, $problem) = @_;

    if ($problem->category eq ROADWORKS_CATEGORY) {
        $self->_post_report_sent_close($problem, 'report/new/roadworks_text.html');
    }
}

=head2 munge_overlapping_asset_bodies

Bristol take responsibility for some parks that are in North Somerset and South Gloucestershire.

To make this work, the Bristol body is setup to cover North Somerset and South Gloucestershire
as well as Bristol. Then method decides which body or bodies to use based on the passed in bodies
and whether the report is in a park.

=cut

sub munge_overlapping_asset_bodies {
    my ($self, $bodies) = @_;

    my $all_areas = $self->{c}->stash->{all_areas};

    if (grep ($self->council_area_id->[0] == $_, keys %$all_areas)) {
        # We are in the Bristol area so carry on as normal
        return;
    } elsif ($self->check_report_is_on_cobrand_asset) {
        # We are not in a Bristol area but the report is in a park that Bristol is responsible for,
        # so only show Bristol categories.
        %$bodies = map { $_->id => $_ } grep { $_->get_column('name') eq $self->council_name } values %$bodies;
    } else {
        # We are not in a Bristol area and the report is not in a park that Bristol is responsible for,
        # so only show other categories.
        %$bodies = map { $_->id => $_ } grep { $_->get_column('name') ne $self->council_name } values %$bodies;
    }
}

sub open311_munge_update_params {
}

sub check_report_is_on_cobrand_asset {
    my ($self) = @_;

    # We're only interested in these two parks that lie partially outside of Bristol.
    my @relevant_parks_site_codes = (
        'ASHTCOES', # Ashton Court Estate
        'STOKPAES', # Stoke Park Estate
    );

    my $park = $self->_park_for_point(
        $self->{c}->stash->{latitude},
        $self->{c}->stash->{longitude},
        'parks',
    );
    return 0 unless $park;

    return grep { $_ eq $park->{site_code} } @relevant_parks_site_codes;
}

sub _park_for_point {
    my ( $self, $lat, $lon, $type ) = @_;

    my ($x, $y) = Utils::convert_latlon_to_en($lat, $lon, 'G');

    my $host = FixMyStreet->config('STAGING_SITE') ? "tilma.staging.mysociety.org" : "tilma.mysociety.org";
    my $cfg = {
        url => "https://$host/mapserver/bristol",
        srsname => "urn:ogc:def:crs:EPSG::27700",
        typename => $type,
        filter => "<Filter><Contains><PropertyName>Geometry</PropertyName><gml:Point><gml:coordinates>$x,$y</gml:coordinates></gml:Point></Contains></Filter>",
        outputformat => 'GML3',
    };

    my $features = $self->_fetch_features($cfg, $x, $y, 1);
    my $park = $features->[0];

    if ($type eq 'flytippingparks') {
        return $park;
    }
    return { site_code => $park->{"ms:parks"}->{"ms:SITE_CODE"} } if $park;
}

sub get_body_sender {
    my ( $self, $body, $problem ) = @_;

    my $emails = $self->feature('open311_email');
    if ($problem->category eq 'Flytipping' && $emails->{flytipping_parks}) {
        my $park = $self->_park_for_point(
            $problem->latitude,
            $problem->longitude,
            'flytippingparks',
        );
        if ($park) {
            $problem->set_extra_metadata('flytipping_email' => $emails->{flytipping_parks});
            return { method => 'Email' };
        }

    }
    return $self->SUPER::get_body_sender($body, $problem);
}

sub munge_sendreport_params {
    my ($self, $row, $h, $params) = @_;

    if ( my $email = $row->get_extra_metadata('flytipping_email') ) {
        $row->push_extra_fields({ name => 'fixmystreet_id', description => 'FMS reference', value => $row->id });

        my $to = [ [ $email, $self->council_name ] ];

        my $witness = $row->get_extra_field_value('Witness') || 0;
        if ($witness) {
            my $emails = $self->feature('open311_email');
            my $dest = $emails->{$row->category};
            push @$to, [ $dest, $self->council_name ];
        }

        $params->{To} = $to;
    }
}

1;
