# Codanna Playbook

Use Codanna as the preferred discovery layer when code ownership, symbol usage,
or repo-doc context matters. Use direct reads and `rg` when Codanna is missing,
stale, or too noisy.

## Default Tool Order

1. `semantic_search_with_context`
2. `analyze_impact`
3. `find_symbol`
4. `search_symbols`
5. `semantic_search_docs`
6. `rg` plus direct file reads as deterministic fallback

## Query Rules

- Include one concrete anchor in every query: file-ish hint, symbol name, module
  name, feature name, or contract name.
- Use `lang: "typescript"` when code search is noisy.
- Start broad enough to find the owner, then narrow with symbols and impact
  analysis.

Useful starting anchors for this repo:

- `RendererIntentEnvelope preload IPC boundary`
- `PlayerSnapshot native helper playback contract`
- `REDACTION_BOUNDARY renderer secrets`
- `Electron main secure storage window lifecycle`
- `import ledger copied Lineup slice`

## Local Semantic Model

For this Desktop repo, prefer the Desktop repo's local code-specialized Codanna
model configuration when initializing or refreshing local settings. This is a
Desktop-local choice for fast code-oriented lookup, tailored discovery, and
offline use; it is not an instruction to import or depend on upstream Lineup
tooling.

- `model = "JinaEmbeddingsV2BaseCode"`
- `threshold = 0.45`

Changing the model requires `codanna index --force` and a document collection
refresh. After a successful force index, `get_index_info` may report semantic
search enabled with `0` embeddings; treat that as an eligible symbol
documentation signal, not an indexing failure.

Codanna creates code embeddings from symbol doc comments, and early Desktop
code often has little symbol-level documentation.

Use `search_documents` for indexed repository docs. Use `search_symbols` or
direct file reads for code until documented production symbols exist.

## Planning Evidence

For serious plans, record:

- query or tool used
- useful symbols or docs found
- impacted files or contracts
- whether Codanna was sufficient
- fallback reads when it was not sufficient

The evidence should justify the chosen owner and scope. It should not become a
transcript.

## Impact Gate

Before changing a shared contract, public type, cross-process payload, or module
owner, run impact analysis when Codanna can identify the symbol. If impact
analysis is unavailable or weak, record the fallback path and inspect imports
with `rg`.

## Local Artifacts

Do not commit Codanna generated state:

- `.codanna/`
- `.fastembed_cache`
- `.mcp_sequential_thinking/`

`.codannaignore` is tracked because it defines what the index should skip.
