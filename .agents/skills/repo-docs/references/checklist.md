# Final checklist

Go through it before reporting. Fix what fails; mention what you could not check.

## Structure and navigation
- [ ] README opens with what the project is, then one whole-system flowchart, then the stage table.
- [ ] Every stage page has prev / home / next links at the top and prev / next at the bottom, in flow order.
- [ ] Every reference page links back to the README.
- [ ] Each fact lives in one place; other pages link to it (`data-formats.md#3-record-row`) instead of copying it.
- [ ] `python3 <skill>/scripts/check_links.py <repo>` reports 0 broken links and anchors.

## Content
- [ ] No decision logs in docs: no "owner decision", decision numbers, dated approvals, "we tried", reviewer names.
      Each is rewritten as the current rule with its reason, or moved to `history/`.
- [ ] Every file shape and API call has a field table and a real, shortened example.
- [ ] Every API call has a setting / value / why table and an errors table.
- [ ] Every number, path, flag, default, field name and test name was checked against the code or by running it.
      Nothing is filled in from memory.
- [ ] Terms are defined where first used (terms table) and in the glossary, with the code that defines them.
- [ ] Status is dated and says what is done, running and not started.
- [ ] Planned work is in `docs/plans/` or marked "Planned", never described as if it exists.

## Safety
- [ ] No keys, tokens, phone numbers, private hostnames or personal data. Key *locations* only.
- [ ] Examples from real user data are synthetic or redacted.

## Mermaid pitfalls
- Quote any label containing spaces, `/`, `(`, `:`, `·` or `|`: `A["full/records/<br/>one row per run"]`.
- `<` and `>` inside labels break rendering; write `#lt;` and `#gt;` (`"#lt;src#gt;.jsonl"`).
- Line breaks inside a label: `<br/>`.
- Edge labels with special characters: `-->|"1 · adapters"|`.
- Shapes: `[("…")]` for a data store, `{{"…"}}` for an external service, `["…"]` for an artifact.
- `flowchart TD` for the whole system (reads top to bottom on narrow screens), `flowchart LR` for one stage.
- Keep a chart under about 12 nodes; split it if it grows.
