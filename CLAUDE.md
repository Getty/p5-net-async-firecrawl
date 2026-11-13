# Net-Async-Firecrawl

IO::Async client for the Firecrawl v2 HTTP API: every endpoint of the synchronous
sibling `WWW-Firecrawl` as a Future-returning method, plus the high-level flows the
synchronous client does not have — start a job, poll until it completes, walk the
pagination chain, split the pages by the success policy.

Released to CPAN as `Net-Async-Firecrawl`, built with `Dist::Zilla` via
`[@Author::GETTY]`. One module — `Net::Async::Firecrawl`, an `IO::Async::Notifier`
subclass — and no script.

The wire format belongs to `WWW-Firecrawl`: the request builders and response parsers
live there, this distribution wraps them. The endpoint contract, the Future contract,
the flow helpers and the result shapes live in skill `net-async-firecrawl-core` — they
are not repeated here.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
the principle is the shared rule `agent-delegation` (skilletor bundle
`getty-cpan-dist@getty`); the lane boundaries are in
`.claude/rules/net-async-firecrawl-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-async-firecrawl-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `net-async-firecrawl-release-manager` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates rather than loading them. Skill sources live under `.claude/skills/` —
`getty-perl-core`, `getty-perl-pod`, `perl-io-async-future` and the karr skills are
installed from the shared sources; `net-async-firecrawl-core` and `perl-firecrawl` are
owned by this repo.

Work is coordinated on the repo's `karr` board (`karr board`).

## State of the code

The flows are covered by a scripted suite (`prove -lr t/`, seven files, no network);
it needs `WWW::Firecrawl` installed, or the sibling checkout on the include path.
`LICENSE`, `Changes`, `README.md`, `cpanfile` and the CI workflow
(`.github/workflows/ci.yml`, pure-Perl test run on the house `dzil-test` action) are
committed; the module carries `our $VERSION`, which the bundle maintains at release.
