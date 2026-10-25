#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Scalar::Util qw( blessed );
use HTTP::Response;
use JSON::MaybeXS qw( encode_json );
use IO::Async::Loop;
use Future;

use Net::Async::Firecrawl;

my $true = JSON::MaybeXS::true();

# Scripted do_request, same pattern as t/10-flows.t.
{
  package Test::Firecrawl::Scripted;
  use parent 'Net::Async::Firecrawl';
  use JSON::MaybeXS qw( encode_json );
  use HTTP::Response;
  use Future;

  sub _init {
    my ( $self, $args ) = @_;
    $self->{script} = delete $args->{script} || [];
    $self->{log}    = [];
    $self->SUPER::_init($args);
  }

  sub do_request {
    my ( $self, $req ) = @_;
    push @{ $self->{log} }, $req->uri.'';
    my $step = shift @{ $self->{script} }
      or return Future->fail("script exhausted for ".$req->method.' '.$req->uri);
    my $body = ref $step->{body} ? encode_json($step->{body}) : ($step->{body} // '');
    return Future->done( HTTP::Response->new(
      $step->{code} // 200, 'OK', [ 'Content-Type' => 'application/json' ], $body,
    ) );
  }
}

{
  package Test::ScriptedHTTP;
  sub new { my ( $class, @resp ) = @_; bless { q => [ @resp ], n => 0 }, $class }
  sub do_request {
    my ( $self, %args ) = @_;
    $self->{n}++;
    return Future->done( shift @{ $self->{q} } );
  }
  sub count { $_[0]->{n} }
}

my $loop = IO::Async::Loop->new;

sub mk_client {
  my ( @script ) = @_;
  my $fc = Test::Firecrawl::Scripted->new(
    base_url => 'http://localhost:9999', poll_interval => 0, script => [ @script ],
  );
  $loop->add($fc);
  return $fc;
}

sub status { HTTP::Response->new( $_[0], 'x', [ 'Content-Type' => 'text/plain' ], 'nope' ) }

# --- job started without an id ------------------------------------------

my %flows = (
  crawl_and_collect     => [ url  => 'https://a' ],
  batch_scrape_and_wait => [ urls => ['https://a'] ],
  extract_and_wait      => [ urls => ['https://a/*'] ],
  agent_and_wait        => [ prompt => 'find it' ],
);

for my $flow ( sort keys %flows ) {
  subtest "$flow: job without id fails with a typed error" => sub {
    my $fc = mk_client( { body => { success => $true } } );
    my @failure = $fc->$flow( @{ $flows{$flow} } )->failure;
    isa_ok $failure[0], 'WWW::Firecrawl::Error';
    ok blessed $failure[0] && $failure[0]->is_api, 'type=api';
    is $failure[1], 'firecrawl', 'failure spec';
    like "$failure[0]", qr/no id/, 'message names the missing id';
  };
}

# --- agent_and_wait -----------------------------------------------------

subtest 'agent_and_wait: processing -> completed' => sub {
  my $fc = mk_client(
    { body => { success => $true, id => 'a1' } },
    { body => { status => 'processing' } },
    { body => { status => 'completed', data => { answer => 42 } } },
  );
  my $res = $fc->agent_and_wait( prompt => 'find it' )->get;
  is $res->{status}, 'completed';
  is $res->{data}{answer}, 42;
  like $fc->{log}[0], qr{/v2/agent$}, 'agent started';
  like $fc->{log}[$_], qr{/v2/agent/a1$}, 'agent_status polled' for 1, 2;
};

subtest 'agent_and_wait: status=failed is a job error' => sub {
  my $fc = mk_client(
    { body => { success => $true, id => 'a2' } },
    { body => { status => 'failed', error => 'agent died' } },
  );
  my @failure = $fc->agent_and_wait( prompt => 'x' )->failure;
  isa_ok $failure[0], 'WWW::Firecrawl::Error';
  ok $failure[0]->is_job, 'type=job';
  like "$failure[0]", qr/agent died/;
  is $failure[1], 'firecrawl';
};

# --- do_request guard ---------------------------------------------------

subtest 'do_request rejects anything but an HTTP::Request' => sub {
  my $fc = Net::Async::Firecrawl->new( base_url => 'http://x' );
  $loop->add($fc);
  like exception { $fc->do_request('GET /') }, qr/do_request requires HTTP::Request/, 'string';
  like exception { $fc->do_request({}) },      qr/do_request requires HTTP::Request/, 'hashref';
  like exception { $fc->do_request() },        qr/do_request requires HTTP::Request/, 'nothing';
};

# --- retry policy follows the sibling's max_attempts --------------------

subtest 'max_attempts => 1 never retries' => sub {
  my $http = Test::ScriptedHTTP->new( status(503), status(503) );
  my $fc = Net::Async::Firecrawl->new(
    base_url => 'http://x', http => $http, max_attempts => 1,
    delay_sub => sub { Future->done },
  );
  $loop->add($fc);
  my @failure = $fc->scrape( url => 'https://x' )->failure;
  isa_ok $failure[0], 'WWW::Firecrawl::Error';
  is $failure[0]->attempt, 1, 'failed on the first attempt';
  is $http->count, 1, 'one request only';
};

subtest 'max_attempts => 5 retries up to five times' => sub {
  my $http = Test::ScriptedHTTP->new( map { status(503) } 1 .. 6 );
  my @delays;
  my $fc = Net::Async::Firecrawl->new(
    base_url => 'http://x', http => $http, max_attempts => 5,
    delay_sub => sub { push @delays, $_[0]; Future->done },
  );
  $loop->add($fc);
  my @failure = $fc->scrape( url => 'https://x' )->failure;
  is $failure[0]->attempt, 5, 'gave up on the fifth attempt';
  is $http->count, 5, 'five requests';
  is scalar @delays, 4, 'four delays between them';
};

subtest 'retry_statuses decides what is retried' => sub {
  my $http = Test::ScriptedHTTP->new( status(503), status(503) );
  my $fc = Net::Async::Firecrawl->new(
    base_url => 'http://x', http => $http, retry_statuses => [ 429 ],
    delay_sub => sub { Future->done },
  );
  $loop->add($fc);
  $fc->scrape( url => 'https://x' )->failure;
  is $http->count, 1, '503 no longer retried';
};

done_testing;
