# VendorGuard - Vendor Risk Scoring and Compliance Monitor
# Agent.md - Team Context and Current Workspace State

## Project Mission
Build an intelligent vendor management platform that monitors
third-party vendors across financial health, cybersecurity posture,
and contractual compliance. The platform should score vendor risk,
detect SLA breaches, summarize obligations, and generate executive
reports using OpenAI `gpt-4o-mini`.

## Current Workspace Status
- The scaffold has been moved to the repository root.
- The active app folders are `backend/`, `frontend/`, and `tests/`.
- Design assets remain at the root in `vendor-risk-platform-spec.md`,
  `schema/vendor-risk-platform.sql`, and `seed/vendor-risk-seed.json`.
- Frontend dependencies are installed.
- Backend dependencies are only partially installed because
  `better-sqlite3` requires a Windows native build path that is not
  fully available on this machine yet.

## Team
- Pod Lead: architecture, GitHub, merges, demo
- Backend Dev: vendor CRUD, DB, SLA engine
- AI Member: OpenAI integration, scoring, reports
- Frontend Dev: React dashboard, components, UI
- QA: Jest tests, Postman, verification

## Tech Stack
- Runtime: Node.js 22.19.0
- Backend: Express.js 4.x
- Database: SQLite via better-sqlite3
- Frontend: React 19 + Vite 5
- AI: OpenAI gpt-4o-mini
- Testing: Jest and Postman
- Language: plain JavaScript

## Current Project Structure
```text
.
|-- Agent.md
|-- README.md
|-- .gitignore
|-- .editorconfig
|-- .prettierrc
|-- vendor-risk-platform-spec.md
|-- schema/
|   `-- vendor-risk-platform.sql
|-- seed/
|   `-- vendor-risk-seed.json
|-- backend/
|   |-- .env
|   |-- .env.example
|   |-- package.json
|   `-- src/
|       |-- server.js
|       |-- config/db.js
|       |-- db/schema.sql
|       |-- controllers/
|       |   |-- vendor.controller.js
|       |   `-- ai.controller.js
|       |-- routes/
|       |   |-- vendor.routes.js
|       |   `-- ai.routes.js
|       |-- services/
|       |   |-- vendor.service.js
|       |   |-- sla.service.js
|       |   `-- ai.service.js
|       `-- middleware/
|           `-- errorHandler.js
|-- frontend/
|   |-- package.json
|   |-- vite.config.js
|   |-- index.html
|   `-- src/
|       |-- main.jsx
|       |-- App.jsx
|       |-- services/api.js
|       |-- components/
|       |   |-- Header.jsx
|       |   |-- StatsBar.jsx
|       |   |-- VendorList.jsx
|       |   |-- VendorDetail.jsx
|       |   |-- AlertPanel.jsx
|       |   |-- RiskReport.jsx
|       |   |-- ContractSummary.jsx
|       |   |-- SLABreaches.jsx
|       |   |-- RiskScoreCard.jsx
|       |   |-- LoadingSpinner.jsx
|       |   `-- EmptyState.jsx
|       `-- styles/
|           `-- app.css
`-- tests/
    |-- vendor.service.test.js
    |-- sla.service.test.js
    `-- VendorRisk.postman_collection.json
```

## Important Change Log
- The original nested `vendor-risk-platform/` wrapper directory is no
  longer part of the active structure.
- `backend/`, `frontend/`, and `tests/` are now first-class root folders.
- The root design files are intended to guide implementation and should
  stay in sync with the code as development proceeds.
- `Agent.md` is the current team context file; there is no separate
  `AGENTS.md` in use right now.

## Implementation Guidance
- Keep backend and frontend concerns separated by folder.
- Use `backend/src/db/schema.sql` for the runtime schema that the app
  will actually execute.
- Treat `schema/vendor-risk-platform.sql` as the authoritative design
  reference unless the app schema intentionally diverges.
- Keep all API calls centralized in `frontend/src/services/api.js`.
- Prefer small services and thin controllers.
- Add logic incrementally; most app files are still empty placeholders.

## API Response Format
Use this response envelope for new endpoints:

```json
{
  "success": true,
  "message": "Human readable message",
  "data": {}
}
```

Use this error envelope for failures:

```json
{
  "success": false,
  "message": "What went wrong",
  "error": "Technical detail"
}
```

## Risk Scoring Rules
- Financial score: `0-100`
- Cyber score: `0-100`
- Compliance score: `0-100`
- Overall score: `(financial * 0.30) + (cyber * 0.40) + (compliance * 0.30)`

Risk levels:
- `80-100`: `LOW`
- `60-79`: `MEDIUM`
- `40-59`: `HIGH`
- `0-39`: `CRITICAL`

## Development Rules
- Plain JavaScript only.
- Use async/await for async flows.
- Validate inputs before database writes.
- Use prepared statements for SQLite access.
- Keep business logic in services, not routes.
- Add comments only where the logic is not obvious.
- Do not hardcode secrets or API keys.

## Setup Notes
- Frontend install is complete and `frontend/node_modules` exists.
- Backend package install needs follow-up because `better-sqlite3`
  currently cannot finish building on this Windows + Node 22 setup
  without the required Visual Studio C++ tooling or a compatible
  prebuilt binary.

## Next Development Focus
1. Finalize the backend SQLite installation path.
2. Implement database bootstrap in `backend/src/config/db.js`.
3. Add vendor and AI route wiring in the backend.
4. Build the dashboard shell in the frontend.
