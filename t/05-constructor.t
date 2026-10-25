#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use IO::Async::Loop;
use WWW::Firecrawl ();

use Net::Async::Firecrawl;

my $loop = IO::Async::Loop->new;

subtest 'retry and classification attributes reach the sibling' => sub {
  my $on_retry = sub { };
  my $fc = Net::Async::Firecrawl->new(
    base_url       => 'http://x',
    max_attempts   => 5,
    retry_backoff  => [ 2, 4 ],
    retry_statuses => [ 503 ],
    on_retry       => $on_retry,
    strict         => 1,
    failure_codes  => [ 404 ],
  );
  $loop->add($fc);
  my $sibling = $fc->firecrawl;
  is $sibling->max_attempts, 5, 'max_attempts';
  is_deeply $sibling->retry_backoff, [ 2, 4 ], 'retry_backoff';
  is_deeply $sibling->retry_statuses, [ 503 ], 'retry_statuses';
  is $sibling->on_retry, $on_retry, 'on_retry';
  ok $sibling->strict, 'strict';
  ok $sibling->is_failure->({ metadata => { statusCode => 404 } }), 'failure_codes';
  ok !$sibling->is_failure->({ metadata => { statusCode => 500 } }), 'failure_codes narrows the policy';
};

subtest 'is_failure is forwarded' => sub {
  my $policy = sub { 1 };
  my $fc = Net::Async::Firecrawl->new( base_url => 'http://x', is_failure => $policy );
  is $fc->firecrawl->is_failure, $policy;
};

subtest 'a prebuilt firecrawl instance carries its own settings' => sub {
  my $sibling = WWW::Firecrawl->new( base_url => 'http://x', max_attempts => 7 );
  my $fc = Net::Async::Firecrawl->new( firecrawl => $sibling );
  is $fc->firecrawl, $sibling, 'instance used as given';
  is $fc->firecrawl->max_attempts, 7;
};

subtest 'firecrawl and forwarded attributes are mutually exclusive' => sub {
  my $sibling = WWW::Firecrawl->new( base_url => 'http://x' );
  like exception {
    Net::Async::Firecrawl->new( firecrawl => $sibling, max_attempts => 5 );
  }, qr/firecrawl.*max_attempts/, 'croaks instead of silently ignoring';
};

subtest 'unknown keys croak with the offending names' => sub {
  like exception {
    Net::Async::Firecrawl->new( base_url => 'http://x', max_attemps => 5, bogus => 1 );
  }, qr/Unknown configuration keys: bogus,max_attemps/;
};

done_testing;
