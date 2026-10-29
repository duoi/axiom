---
name: repo-docs
description: Write or overhaul a repository's README and docs/ so a newcomer can grok the project at first look and click through the whole flow - a README with a Mermaid flowchart and a stage table, one page per stage with its own flowchart and prev/next links, reference pages for every file shape and API call (field tables, real examples, a "why" for each setting), a glossary, an operations page, CONTRIBUTING recipes, and process records moved out to history/. Use this whenever the user asks to document a repo, write or fix READMEs, "make the docs readable", clean up docs or old notes before publishing a repo, explain how things flow, document schemas or API shapes, or make a project contributable - even if they only say "add real documentation" or "can someone follow this?".
---

# Repo docs

Produce documentation that someone new can open, understand in a minute, and then follow stage by stage to every
file, schema and API call - without ever needing to read the history of how decisions were made.

## What good looks like

A reader lands on the README and sees, in order: what the project does (3-4 sentences), **one flowchart of the
whole system**, a table of stages linking to one page each, reference pages, current status, a quick start, and the
repo layout. Every page they click opens with navigation links, its own flowchart, and a table of its inputs, code,
outputs and how to run it, and ends with a link to the next stage. Every file format and every external API is in one
reference page with field tables and a real, shortened example. That is the whole idea: **observe the full flow,
then click through it**.

## Principles (and why)

- **Conclusions, not decision logs.** Docs state the rule as it is now, with its reason ("pinned to one endpoint:
  the same model scores differently across hosts"). Never "Owner decision 33 (2026-10-24, 'sounds good')", never
  "we tried X then Y". A contributor needs the rule and the why; the story of how it was reached is noise to them.
  Process records (audit logs, review requests, validation reports, A/B write-ups) go in `history/` with a short
  README saying the reader does not need them.
- **Shapes are first-class.** Anything the code reads, writes or sends - files, rows, configs, HTTP requests and
  responses - gets a section: a field table (field, type, meaning), a real example cut down to the interesting
  parts, and who writes and reads it. For API calls add a **setting / value / why** table: every parameter the code
  sends and the reason it is set that way. This is the part readers come back to most.
- **Flowcharts everywhere the data moves.** One for the whole system in the README, one per stage page, one at the
  top of the data-formats page mapping each shape (§ numbers) to the step that writes it. Label edges with the
  script that does the step and nodes with the file path.
- **Click-through navigation.** Stage pages carry `[← previous] · [Docs home] · [Next →]` at the top and the bottom.
  Reference pages link back to the README. Tool-folder READMEs link to the concept pages, and concept pages link to
  the shapes. A reader should never hit a dead end or a page with no way back.
- **One writer.** Write all pages yourself in one pass, or hand the whole job to a single helper agent. Several parallel
  writers produce mismatched structure, terms and tone, and the user has to pay for a second editing pass. Use
  helpers only for read-only fact gathering, if at all.
- **Verified, not remembered.** Every number, path, field name, default, flag and test name comes from the code or
  from running something. If you cannot check a fact, leave it out. A confident wrong detail in docs costs more than
  a missing one.
- **Plain words.** Short sentences, everyday words, a term defined the first time it appears (a terms table at the
  top of a stage page works well). Tables over prose for anything with more than two attributes.
- **No secrets.** Describe where keys live (`~/.config/<project>/<provider>.key`) and that they are never committed;
  never paste a key, token, phone number or private endpoint.

## Workflow

1. **Survey.** Read the existing README, docs, top-level scripts and entry points, configs, tests and the data
   paths the code uses. List every stage the data passes through, every file shape, every external API, and every
   term a newcomer would trip on. Note what is stale (old paths, removed flags, superseded notes).
2. **Map the flow.** Sketch the end-to-end flowchart first. The stages in it become the docs pages. For a project
   that is not a pipeline, use what moves in it instead: a request's path through a service, a library's main call
   path, or the build/deploy flow. See `references/adapting.md`.
3. **Plan the pages.** Use the layout below; drop pages the project does not need and do not invent stages to fill
   it. Decide where each fact lives once, and link to it from everywhere else instead of repeating it.
4. **Write**, using the templates in `references/templates.md`. Order: data-formats (shapes) and glossary first,
   since the stage pages link into them; then the stage pages in flow order; then the README, CONTRIBUTING,
   operations and folder READMEs.
5. **Clean up.** Move process records into `history/`. Delete archives and old notes that git history already
   keeps, after saying which commit holds them (`git show <sha>:<path>`). Remove decision numbers, owner quotes and
   "we decided" passages from the docs, and rewrite each as a rule with its reason.
6. **Verify.** Run `python3 scripts/check_links.py <repo>` (bundled with this skill) for broken relative links and
   anchors. Then go through `references/checklist.md`: facts against code, Mermaid syntax, navigation, secrets.
7. **Report.** Tell the user what pages exist, what moved or was deleted, and anything you could not verify.

## Layout

```
README.md                  what it is · whole-system flowchart · stage table · reference table · status · quick start · layout
CONTRIBUTING.md            setup · data you need · running tests · step-by-step recipes for common changes
docs/
  overview.md              the problem · what the system answers/does · the pipeline with file names · where data lives · current state
  <stage>.md               one per stage, titled "Stage N · Name": nav, flowchart, inputs/code/outputs/run table, terms, how it works, nav
  data-formats.md          every file and API shape: §-numbered sections, field tables, real examples, why-tables for API calls
  schema.md                (if the project has a domain schema: labels, entities, config) definitions and boundaries
  glossary.md              every project term with a one-line definition and the code that defines it
  operations.md            rules that always apply · where data lives · keys · how to run the heavy/paid jobs · checking a run
  licences.md              (if data or dependencies carry licence constraints)
  plans/                   planned, not built work, clearly marked as such
tools/<folder>/README.md   command reference for that folder, linking to the concept pages
history/README.md          process records and how to find older ones in git history
```

A README status section is fine and useful: it is the current state, dated. What does not belong is the record of
how the state was reached.

## Files in this skill

- `references/templates.md` - copy-ready skeletons for each page type, taken from a repo the user liked. Read it
  before writing.
- `references/adapting.md` - how to map the layout onto services, libraries and apps that are not data pipelines.
- `references/checklist.md` - the final pass, including Mermaid pitfalls.
- `scripts/check_links.py` - checks every relative Markdown link and `#anchor` in a repo (stdlib only).
