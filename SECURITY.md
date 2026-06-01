# Security

## Reporting

Report vulnerabilities privately via GitHub Security Advisories on this
repository. Please do not open public issues for security reports.

## Handling secrets

banto routes all LLM and embedding traffic through a
[sekisho](https://github.com/Taure/sekisho) gateway; provider keys live there,
not in banto. Never commit real keys or gateway tokens. Runtime configuration
is supplied via the `BANTO_*` environment variables and `sys.config`.

## Dependency advisories

CI runs `rebar3 audit` and fails on any advisory of severity `low` or higher.
Advisories that have no upstream fix and do not apply to banto are listed here
and skipped via the `audit-ignores` CI input. Each entry is revisited when an
upstream fix ships.

None currently.
</content>
