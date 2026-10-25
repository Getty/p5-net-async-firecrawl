#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use IO::Async::Loop;
use Net::Async::Firecrawl;

# Needs a running Firecrawl instance:
#   FIRECRAWL_BASE_URL=http://localhost:3002 perl -Ilib ex/live_handyintelligence.pl [URL]
# FIRECRAWL_API_KEY is optional for a self-hosted instance. URL is the site to
# scrape, map and crawl (default https://handyintelligence.com).
my $base_url = $ENV{FIRECRAWL_BASE_URL}
  or die "FIRECRAWL_BASE_URL is not set: point it at a running Firecrawl instance,\n"
       . "e.g. FIRECRAWL_BASE_URL=http://localhost:3002\n";
my $target = shift // 'https://handyintelligence.com';

my $loop = IO::Async::Loop->new;
my $fc = Net::Async::Firecrawl->new(
  base_url      => $base_url,
  ( defined $ENV{FIRECRAWL_API_KEY} ? ( api_key => $ENV{FIRECRAWL_API_KEY} ) : () ),
  poll_interval => 2,
);
$loop->add($fc);

say "=== scrape $target ===";
my $doc = $fc->scrape(
  url     => $target,
  formats => ['markdown'],
)->get;
say "title: ", $doc->{metadata}{title} // '(none)';
say "status: ", $doc->{metadata}{statusCode} // '?';
say "markdown length: ", length($doc->{markdown} // '');
say "first 400 chars:";
say substr($doc->{markdown} // '', 0, 400);

say "\n=== map $target ===";
my $links = $fc->map( url => $target, limit => 50 )->get;
say "found ", scalar(@$links), " links";
say "  - ", ($_->{url} // $_) for @{$links}[ 0 .. ($#$links > 9 ? 9 : $#$links) ];

say "\n=== crawl_and_collect (limit 5) ===";
my $crawl = $fc->crawl_and_collect(
  url   => $target,
  limit => 5,
  scrapeOptions => { formats => ['markdown'] },
)->get;
say "status: $crawl->{status}";
say "pages: ", scalar @{ $crawl->{data} || [] };
for my $p (@{ $crawl->{data} }) {
  my $url = $p->{metadata}{sourceURL} // $p->{metadata}{url} // '?';
  my $len = length($p->{markdown} // '');
  say "  - $url  (md=${len} chars)";
}
