# Net::Async::Firecrawl

IO::Async client for the [Firecrawl](https://firecrawl.dev) v2 API. Returns `Future` objects; handles polling, pagination, and partial-success flows automatically.

## Synopsis

```perl
use IO::Async::Loop;
use Net::Async::Firecrawl;

my $loop = IO::Async::Loop->new;
my $fc = Net::Async::Firecrawl->new(
  base_url      => 'http://localhost:3002',  # self-hosted
  poll_interval => 3,
);
$loop->add($fc);

# Single scrape
my $doc = $fc->scrape( url => 'https://example.com', formats => ['markdown'] )->get;

# Crawl and collect all pages (polls + follows pagination)
my $result = $fc->crawl_and_collect(
  url   => 'https://example.com',
  limit => 100,
)->get;
# $result->{data}     — ok pages
# $result->{failed}   — failed pages (url/statusCode/error/page)
# $result->{raw_data} — all pages (original order)
# $result->{stats}    — { ok, failed, total }

# Batch scrape and wait
my $batch = $fc->batch_scrape_and_wait(
  urls    => ['https://a', 'https://b'],
  formats => ['markdown'],
)->get;

# Structured extraction
my $extract = $fc->extract_and_wait(
  urls   => ['https://example.com/*'],
  prompt => 'extract pricing and product names',
)->get;

# Concurrent scrape (partial-success)
my $many = $fc->scrape_many(
  ['https://a', 'https://b', 'https://c'],
  formats => ['markdown'],
)->get;
# $many->{ok}     — [{ url, data }, ...]
# $many->{failed} — [{ url, error }, ...]

# Retry failed pages from a previous crawl
my $retried = $fc->retry_failed_pages( $result, formats => ['markdown'] )->get;
```

## Error Handling

All failures resolve as `Future->fail($error, 'firecrawl')` where `$error` is a `WWW::Firecrawl::Error` (stringifies to message):

```perl
my $f = $fc->scrape( url => 'https://example.com' );
my ($err) = $f->failure;
if ($err && ref $err && $err->isa('WWW::Firecrawl::Error')) {
  if ($err->is_transport) { ... }
  if ($err->is_api)       { ... }
  if ($err->is_job)       { ... }  # crawl/extract/agent completed with status=failed
}
```

Job-level failures (`status: failed` or `cancelled`) always fail the Future regardless of other settings.

## All Endpoints

Every endpoint from `WWW::Firecrawl` is available as a Future-returning method with identical argument signature:

```perl
$fc->scrape(...)          $fc->crawl(...)
$fc->crawl_status($id)   $fc->crawl_cancel($id)
$fc->map(...)             $fc->search(...)
$fc->batch_scrape(...)    $fc->extract(...)
$fc->agent(...)           $fc->credit_usage
# ... and more
```

## Constructor Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `base_url` | `$ENV{FIRECRAWL_BASE_URL}` or cloud URL | Firecrawl server |
| `api_key` | `$ENV{FIRECRAWL_API_KEY}` | Bearer token (optional for self-hosted) |
| `poll_interval` | `3` | Seconds between status polls in flow helpers |
| `api_version` | sibling default | API version, forwarded to `WWW::Firecrawl` |
| `max_attempts` | `3` | Retry attempts for transport/API errors (forwarded) |
| `retry_backoff` | `[1, 2, 4]` | Seconds between retries (forwarded) |
| `retry_statuses` | `[429, 502, 503, 504]` | HTTP statuses that are retried (forwarded) |
| `on_retry` | none | Callback `($attempt, $delay, $error)` before each retry (forwarded) |
| `is_failure`, `failure_codes`, `strict` | sibling default | Classification policy (forwarded) |
| `firecrawl` | auto | Pre-built `WWW::Firecrawl` instance instead of the forwarded keys; combining both croaks |
| `http` | auto | Pre-built `Net::Async::HTTP` instance |

## See Also

- [WWW::Firecrawl](https://metacpan.org/pod/WWW::Firecrawl) — sync client (LWP-based)
- [IO::Async](https://metacpan.org/pod/IO::Async)
- [Firecrawl API docs](https://docs.firecrawl.dev/api-reference/v2-introduction)
