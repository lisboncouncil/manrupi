package FixMyStreet::MapIt;

use FixMyStreet;
use mySociety::MaPit;

my %_mapit_cache;

sub call {
    my ($url, $params, %opts) = @_;

    # 'area' always returns the ID you provide, no matter its generation, so no
    # point in specifying it for that. 'areas' similarly if given IDs, but we
    # might be looking up types or names, so might as well specify it then.
    $opts{generation} = FixMyStreet->config('MAPIT_GENERATION')
        if !$opts{generation} && $url ne 'area' && FixMyStreet->config('MAPIT_GENERATION');

    # Cache MapIt results in-process to avoid repeated HTTP calls
    my $cache_key = "$url/$params/" . join(',', map { "$_=$opts{$_}" } sort keys %opts);
    if (exists $_mapit_cache{$cache_key}) {
        return $_mapit_cache{$cache_key};
    }

    my $result = mySociety::MaPit::call($url, $params, %opts);
    $_mapit_cache{$cache_key} = $result;
    return $result;
}

1;
