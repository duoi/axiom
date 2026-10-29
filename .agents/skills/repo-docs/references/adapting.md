# Adapting the layout

The layout was built for a data pipeline, where "stages" are obvious. Most repos have a flow too; find what moves
and make that the spine of the docs.

| Kind of repo | What flows | Stage pages become | data-formats.md holds |
|---|---|---|---|
| Data / ML pipeline | data, file to file | one page per transform | every file row, config, external API call |
| Web service / API | a request | ingress → auth → handlers → storage → async jobs | every endpoint's request and response, DB tables, queue messages, webhooks |
| Library / SDK | a call from the user's code | the main entry points and the layers under them | public types, config objects, wire formats, errors |
| CLI tool | a command | one page per command group | config file, input and output files, exit codes |
| App (mobile, web, desktop) | a user journey and its data | one page per main screen or feature, then sync and storage | API calls to the backend, local storage, events |
| Infra / deployment | a change, from commit to production | build → test → deploy → run → observe | config and manifest shapes, pipeline variables, secrets layout (names only) |

Rules that carry over unchanged:

- One whole-system flowchart in the README; one flowchart per page.
- Every shape and every external call gets a field table, a real example and, for calls, a why-table.
- Conclusions, not decision logs; process records in `history/` (create it only if there are any).
- Prev/next navigation along the flow; every page links home.

Scale the page count to the repo. A 2,000-line library may need only a README with the flowchart, one
`docs/reference.md` (shapes and API) and CONTRIBUTING. Do not create empty pages to complete the layout.
