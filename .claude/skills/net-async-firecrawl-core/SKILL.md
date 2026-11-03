---
name: net-async-firecrawl-core
description: "Net-Async-Firecrawl — module map, Future contract, flow helpers, result shapes and traps of the IO::Async client for the Firecrawl v2 API. Use when working in lib/Net/Async/Firecrawl.pm."
---

# Net-Async-Firecrawl — what this repository is

One module, one distribution: an `IO::Async::Notifier` subclass that turns the
synchronous **WWW-Firecrawl** client into Future-returning methods and adds the
high-level flows (start job → poll → collect pages → split by success) that the
synchronous client does not have.

The division of labour: WWW-Firecrawl owns the wire format (request builder,
response parser, classification policy, retry decision), this distribution owns the
async plumbing (dispatch, polling, pagination walk, partial-success splitting).

| File | Holds |
|---|---|
| `lib/Net/Async/Firecrawl.pm` | everything: endpoints, flow helpers, retry, POD |
| `t/00-load.t` | load check |
| `t/05-constructor.t` | constructor keys, forwarding to the sibling, rejection of unknown keys |
| `t/10-flows.t` | scrape, map, crawl_and_collect, batch, extract, error propagation, job failure |
| `t/15-scrape-many.t` | concurrent scrape with partial success |
| `t/20-retry.t` | retry, backoff, Retry-After, exhausted attempts |
| `t/30-retry-failed-pages.t` | retry of the failed entries of a prior result |
| `t/40-flow-edges.t` | flows that start without an id, `agent_and_wait`, job failure |
| `ex/live_handyintelligence.pl` | live example against a self-hosted Firecrawl |

## The endpoint layer is generated, not written per endpoint

`@ENDPOINTS` lists the endpoint names; `_install_wrapper` installs one method per
name into the package. The wrapper builds the request with the sibling's
`${name}_request`, dispatches it, and parses the response with
`parse_${name}_response` — the two halves WWW-Firecrawl already owns. Two extra
wrappers (`crawl_status_next`, `batch_scrape_status_next`) reuse the status parser
with a pagination builder.

Consequences:

- A new endpoint is a name in `@ENDPOINTS` — but only after the sibling has the
  matching builder and parser. This distribution never defines a wire format.
- The argument signature is the sibling's, unchanged: `scrape(url => ..., formats =>
  [...])` means exactly what it means there.
- The method resolves to the **parsed payload** (a hashref or arrayref), not to an
  `HTTP::Response`. Only `do_request` returns the raw response.

## Constructor and configuration

Accepted keys: `base_url`, `api_key`, `api_version` (forwarded to WWW-Firecrawl),
`firecrawl` (a pre-built sibling instance, overrides the three above), `http` (a
pre-built `Net::Async::HTTP`), `poll_interval` (seconds between status polls,
default 3), `delay_sub` (a CodeRef returning a Future for every delay — the test
hook).

Everything else is rejected by `configure_unknown` with
`Unknown configuration keys: …`.

The retry attributes (`max_attempts`, `retry_backoff`, `retry_statuses`, `on_retry`)
and the classification attributes (`is_failure`, `failure_codes`, `strict`) are
accepted too and forwarded to the sibling `WWW::Firecrawl->new`; the wrapper reads
them from `$self->firecrawl`. Combined with a prebuilt `firecrawl` instance they
croak — configure that instance itself.

## The Future contract

Every failure resolves as `Future->fail($error, 'firecrawl', $attempt?)`, where
`$error` is a `WWW::Firecrawl::Error`. `$f->failure` therefore returns
`($error, 'firecrawl', $attempt?)`. The error types are the sibling's five:

| Type | Raised when |
|---|---|
| `transport` | Firecrawl unreachable — retried up to `max_attempts` |
| `api` | non-2xx or `{success: false}` — retried only for `retry_statuses` |
| `job` | a flow reports `status: failed` or `status: cancelled` — never retried |
| `scrape` | a single scrape's target was classified as failed — only with `strict` |
| `page` | a target URL inside a flow failed — surfaced in `failed[]`, not thrown |

`Future->fail` with a plain string instead of an error object breaks this contract
and breaks the README idiom `$err->is_transport` at the call site.

The outer Future of `scrape_many` never fails for a per-URL failure; it fails only
for local errors (no loop, bad arguments).

## Flow helpers

All four follow the same shape:

| Helper | Starts | Polls | Result |
|---|---|---|---|
| `crawl_and_collect` | `crawl` | `crawl_status` | full result hash |
| `batch_scrape_and_wait` | `batch_scrape` | `batch_scrape_status` | full result hash |
| `extract_and_wait` | `extract` | `extract_status` | the final status hash |
| `agent_and_wait` | `agent` | `agent_status` | the final status hash |

`crawl_and_collect` and `batch_scrape_and_wait` resolve to:

```
{
  status      => 'completed',
  data        => [ ok_page, ... ],              # only the pages the policy accepts
  failed      => [ { url, statusCode, error, page }, ... ],
  raw_data    => [ page, ... ],                 # every page, original order
  stats       => { ok, failed, total },
}
```

`extract_and_wait` and `agent_and_wait` resolve to the raw status hash — they do not
split pages, because extraction returns a result document, not pages.

Polling uses `Future::Utils::repeat`: on every round the status callback is fired,
`failed`/`cancelled` fail the Future with `type=job`, `completed` ends the loop, and
anything else waits `poll_interval` seconds (the helper's own `poll_interval`
argument overrides the instance default) before the next round.

The split is the sibling's `is_failure` policy, applied page by page. A page without
`metadata` counts as OK. The URL of a failed page is `metadata.sourceURL` or
`metadata.url` — a page with neither yields an undefined URL.

## Pagination

`_collect_pages` follows the `next` URL of a status response verbatim: the URL is
used as given, not rebuilt from the job id. The collected pages keep the order of
the chain, the result keeps the fields of the first status response.

## scrape_many and retry_failed_pages

`scrape_many(\@urls, %common_scrape_args)` fires one `scrape` per URL concurrently
and resolves to `{ ok => [{url, data}], failed => [{url, error}], stats }`. A page
the policy calls failed lands in `failed` with a `WWW::Firecrawl::Error` of type
`page`; a transport or api error lands there with the error it produced.

`retry_failed_pages($result, %scrape_opts)` takes the URLs of `$result->{failed}` and
runs them through `scrape_many` again. It works on a result of `scrape_many` and on
one of the collect helpers — the failed entries carry a `url` in both shapes.

## The retry path

`_do_request_with_retry` sends the request and asks the sibling for the verdict:
`$fc->_classify_response($response, $attempt)` returns `($error, $retryable)`, and
`$fc->_retry_delay($response, $attempt)` returns the backoff (the `Retry-After`
header wins only when it is a plain integer). The attempt counter starts at 1, the
last attempt is `max_attempts`, `on_retry` is called with
`($attempt, $delay, $error)` before the delay, and the failure carries the attempt
number.

Both helpers are **private** in WWW-Firecrawl — an underscore, no API promise. They
are the version-fragile point of this distribution.

## Traps

- `use Future::Utils qw( repeat )` — `Future::Utils` is a separate distribution and
  must be in the cpanfile. The poll loops do not work without it.
- The sibling's private helpers (`_classify_response`, `_retry_delay`) are not API.
- `configure_unknown` rejects every key outside the list in the constructor section.
- All four flow helpers fail a job that starts without an id with a
  `WWW::Firecrawl::Error` of type `api`.
- `http` is built lazily and parented to the notifier; passing your own `http`
  instance skips that parenting and the `user_agent` from the sibling.
- `poll_interval` is a read/write accessor for the instance default; the flow
  helpers take their own `poll_interval` argument, which wins.
- `[@Author::GETTY]` checks the committed `LICENSE` against `dist.ini`.
- `WWW::Firecrawl` is not installed in every checkout — the suite needs it on the
  include path (`prove -I…/p5-www-firecrawl/lib -lr t/`); that is a local
  environment fact, not a reason to install modules.

## Tests

`prove -lr t/` — no network: the tests replace `do_request` with a scripted table.

## Vocabulary

| Term | Means |
|---|---|
| wrapper | one generated Future-returning endpoint method |
| flow helper | start job → poll → collect → split |
| script | the canned response table a test feeds to `do_request` |
| collect | the pagination walk over the `next` chain |
| split | the `is_failure` classification into `data` and `failed` |
