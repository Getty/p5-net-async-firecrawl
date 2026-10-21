# Net-Async-Firecrawl House Rules

Apply to every task in this repository unless explicitly overridden. Bias: caution over
speed on non-trivial work; use judgment on trivial tasks. Loaded automatically at launch
(same priority as `CLAUDE.md`). Subagents get their conventions from the skills
force-loaded via `briefing.skills` — this file is for the orchestrating agent. Perl
conventions live in `getty-perl-core`/`getty-perl-pod`, the async patterns in
`perl-io-async-future`, the contract in `net-async-firecrawl-core`; don't repeat them.

## Engineering discipline

1. **Think before coding** — State assumptions. When uncertain, ask rather than guess.
   Push back when a simpler approach exists. Stop when confused; name what's unclear.
2. **Simplicity first** — Minimum code that solves the problem, nothing speculative;
   a new dependency needs a real justification. Touch only what you must; match the
   existing layout.
3. **Tests verify intent, not just behavior** — Reproduce a bug before fixing it; leave
   a regression test behind. The Future contract, the error types, the result shapes
   and the retry decision are the product — a test that can't fail when they change is
   not a test.
4. **Match the codebase's conventions, even if you disagree** — Conformance > taste;
   surface a harmful convention instead of forking silently. Fail loud: "Done" is wrong
   if anything was skipped silently, "Tests pass" is wrong if any were skipped.
5. **A red test is a claim before it is a failure** — Before changing code to turn a test
   green, say what it asserts and whether your fix keeps that claim or replaces it.

## Delegation

- **You can spawn subagents** (orchestrating main agent): Do NOT touch behavior-relevant
  code yourself — delegate. Your lane: coordinate, inspect, plan, review diffs, run tests,
  edit non-behavioral docs. Why: only the `net-async-firecrawl-*` agents get their skills
  force-loaded; you get no briefing and would touch the Future contract with too
  little context.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code | `net-async-firecrawl-worker` (default) |
  | Commits, `Changes`, card → done, pre-release audit | `net-async-firecrawl-release-manager` |

- **You cannot spawn subagents** (you ARE a `net-async-firecrawl-*` agent): The delegation
  lock does not apply — implement, refactor, debug and test per these rules.

Behavior-relevant = anything in `lib/`, the tests, the endpoint wrappers, the flow
helpers, the result shapes and the error contract. Docs wording is not.

**Only `net-async-firecrawl-release-manager` commits.** A worker leaves a commit-ready
tree and hands its card to `review`; you then dispatch
`net-async-firecrawl-release-manager` to cut the commit and close the card.

## The binding contract is the product — don't regress it silently

Every endpoint here is a Future-returning wrapper around the sibling WWW-Firecrawl's
request builder and response parser — the wire format belongs to that distribution,
and a change there changes this one too. Every failure resolves the Future with a
`WWW::Firecrawl::Error` and the spec `('firecrawl')`; a bare string breaks the
contract and the README idiom with it. The flow helpers resolve to
`{ data, failed, raw_data, stats }`, split by the sibling's `is_failure` policy.
Contract table: skill `net-async-firecrawl-core`.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in scope —
don't invoke the skill first, just use it. Board state lives in `refs/karr/*`.
`karr list --compact` / `karr board` / `karr show ID` read · `karr create "Title"
--priority high --tags a,b --body '…'` files · `karr edit ID -a "note" --claim NAME
--block "why"` updates · `karr move ID in-progress --claim NAME` starts ·
`karr handoff ID --claim NAME --note "…"` hands to review · mutating commands auto-sync.

Card life cycle: you claim and hand out → the worker notes and ends at `review` → the
release-manager commits and moves it to `done`. **Serialize board mutations when fanning
out** — keep implementation work parallel if you like, but collect the results and then
loop the `karr move`/`handoff`/`sync` calls sequentially; N of them landing at once is a
resource event. Command surface: skill `kanban-issues-karr-coordination`.

## Release — never without permission

`dzil build` / `dzil test` / `prove -lr t/` are fine anytime. `dzil release` and any
CPAN upload are STRICTLY forbidden without the maintainer's explicit go-ahead — even if
a plan lists "release" as the next step. Stop and ask.

The last release in this repo's history is 0.001 (2026-04-18); the module stands at
0.002, the next unreleased number — derived at release time, never copied back from
CPAN. The CPAN status is never a blocker and never a ticket.

## Public issues — never act without instruction

`karr` is the internal agent board, churned freely. The GitHub issue tracker carries
real people's reports, written under the maintainer's account. Never act on a public
issue on your own initiative — not even to read it: no listing, viewing, commenting,
closing or creating unless the user explicitly says to handle a specific one.
