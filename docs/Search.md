<!-- harnez:variant=lite -->
# Search Practice (Lite)

- Use `harnez find code "query"` or `harnez find docs "query"` before broad shell searches; MCP uses `harnez_find`.
- `--via NAME` selects one finder; `-k N` limits results; `--json` and `--jsonl` return structured records (`path`, `line`, `title`, `snippet`, `score`, `kind`).
- Read finder status diagnostics: results can be partial after timeout, backend errors, or missing indexes. neus indexes a root once when first needed; do not rerun a query to refresh it.
- Use direct `rg` for exact strings, regex, or known files. The code fallback invokes `rg` when neus is unavailable.
- Configure finders in `~/.harnez/config.yaml`; repository `config.yaml` overrides a user finder by name. Use `name`, `scope`, argv-list `command`, and positive `timeout`; placeholders are `{query}`, `{root}`, `{k}`. Commands run without a shell.

<!-- harnez:stop -->
