# Net-Async-Firecrawl House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

IO::Async Firecrawl v2 client with flow helpers, built on the sibling WWW-Firecrawl. A new
dependency needs a real justification.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-async-firecrawl-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `net-async-firecrawl-release-manager` |
| Read-only research, audit, gap analysis | `net-async-firecrawl-worker` ("read-only, change nothing") |

Behavior-relevant = anything in `lib/`, the tests, the endpoint wrappers, the flow helpers,
the result shapes and the error contract. Docs wording is not.

## The binding contract is the product — don't regress it silently

Every endpoint here is a Future-returning wrapper around the sibling WWW-Firecrawl's request
builder and response parser — the wire format belongs to that distribution, and a change
there changes this one too. Every failure resolves the Future with a `WWW::Firecrawl::Error`
and the spec `('firecrawl')`; a bare string breaks the contract and the README idiom with it.
The flow helpers resolve to `{ data, failed, raw_data, stats }`, split by the sibling's
`is_failure` policy. The Future contract, the error types, the result shapes and the retry
decision are the product — a test that can't fail when they change is not a test. Contract
table: skill `net-async-firecrawl-core`.

## Perl specifics — reference, don't restate

Perl conventions live in `getty-perl-core`/`getty-perl-pod`, the async patterns in
`perl-io-async-future`, the contract in `net-async-firecrawl-core`.
