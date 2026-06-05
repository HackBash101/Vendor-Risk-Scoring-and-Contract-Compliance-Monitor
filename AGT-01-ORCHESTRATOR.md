# AGT-01 — Orchestrator Agent
> **ID:** AGT-01 | **Owner:** Dev 1 | **When:** Hour 2
> **File:** `backend/agents/orchestrator.py`
> **Layer:** Coordination | **Pattern:** Chain of Responsibility · Circuit Breaker

---

## Purpose
Routes all incoming actions to the correct agents, runs agents in parallel where possible,
handles retries on failure, and returns a unified aggregated result.
Nothing in the platform executes without passing through this agent first.

---

## Architecture Position
```
FastAPI Routes
      │
      ▼
┌─────────────────────────┐
│   ORCHESTRATOR AGENT    │  ← You are here
│  AGT-01                 │
└──┬──────┬──────┬────────┘
   │      │      │
AGT-02  AGT-03  AGT-04
Contract Financial Cyber
         │      │
         └──────┘
              │
           AGT-05
           Report
```

---

## Codex Prompt

```
Goal:
Build the Orchestrator Agent that coordinates all 4 other agents,
routes incoming actions, handles retries, and returns aggregated results.

Context:
- @AGENTS.md
- @backend/models/models.py
- @backend/exceptions.py

File to create:
  backend/agents/orchestrator.py

Step 1 — Define these in backend/exceptions.py:
  class VendorRiskException(Exception):
      error_code: str = "INTERNAL_ERROR"
      http_status: int = 500
  class VendorNotFoundException(VendorRiskException):
      error_code = "VENDOR_NOT_FOUND"; http_status = 404
  class AgentException(VendorRiskException):
      error_code = "AGENT_FAILURE"; http_status = 500
  class FileValidationException(VendorRiskException):
      error_code = "INVALID_FILE"; http_status = 400
  class DuplicateVendorException(VendorRiskException):
      error_code = "VENDOR_ALREADY_EXISTS"; http_status = 409

Step 2 — Define in orchestrator.py:
  class OrchestratorAction(Enum):
      SCORE_VENDOR    = "SCORE_VENDOR"
      PARSE_CONTRACT  = "PARSE_CONTRACT"
      FULL_ASSESSMENT = "FULL_ASSESSMENT"
      GENERATE_REPORT = "GENERATE_REPORT"

  @dataclass
  class OrchestratorResult:
      action:        OrchestratorAction
      vendor_id:     int
      results:       dict          # keyed by agent name
      failed_agents: list[str]
      duration_ms:   float

Step 3 — Implement execute() method:
  async def execute(
      self,
      action: OrchestratorAction,
      vendor_id: int,
      db: Session,
      **kwargs
  ) -> OrchestratorResult:

  Routing table:
    SCORE_VENDOR:
      Run financial_scoring_agent.score_vendor_financial() AND
      cybersecurity_posture_agent.score_vendor_cyber() IN PARALLEL
      using asyncio.gather(return_exceptions=True)
      Collect both results even if one fails

    PARSE_CONTRACT:
      Run contract_parsing_agent.parse_contract()
      Pass pdf_path from kwargs

    FULL_ASSESSMENT:
      Run in order: financial → cyber → contract → report_risk
      Pass results forward between agents

    GENERATE_REPORT:
      Run report_risk_agent.generate_risk_report() only

Step 4 — Retry + circuit breaker:
  - Wrap every agent call in try/except AgentException
  - On failure: sleep(1), retry ONCE
  - If retry also fails: append agent name to failed_agents, continue
  - NEVER raise from execute() — always return OrchestratorResult
  - Measure and log duration_ms for every agent call

Step 5 — Structured logging (mandatory):
  logger = logging.getLogger(__name__)
  Log "Agent {name} started  vendor_id={id}"
  Log "Agent {name} completed {ms}ms"
  Log "Agent {name} FAILED {err} — retrying"
  Log "Agent {name} FAILED after retry — skipped"

Constraints:
  - asyncio.gather() for SCORE_VENDOR — must be parallel, not sequential
  - Type hints on ALL signatures
  - Google-style docstring on execute()
  - No business logic here — routing and error-handling only
  - Max function length 50 lines

Done-when:
  - execute() handles all 4 OrchestratorAction values correctly
  - Parallel scoring verified with asyncio.gather
  - Failed agent does not block the pipeline
  - OrchestratorResult ALWAYS returned, never raises
  - All 5 pytest test cases pass
```

---

## Interface Contracts

### Input
```python
action:    OrchestratorAction   # SCORE_VENDOR | PARSE_CONTRACT | FULL_ASSESSMENT | GENERATE_REPORT
vendor_id: int                  # must exist in vendors table
db:        Session              # SQLAlchemy session
**kwargs                        # pdf_path (str) required for PARSE_CONTRACT
```

### Output — OrchestratorResult
```python
@dataclass
class OrchestratorResult:
    action:        OrchestratorAction
    vendor_id:     int
    results:       dict           # { "financial": FinancialScoringOutput, "cyber": ... }
    failed_agents: list[str]      # names of agents that failed after retry
    duration_ms:   float          # total wall-clock time
```

---

## Exception Hierarchy
```python
class VendorRiskException(Exception):
    error_code: str = "INTERNAL_ERROR"
    http_status: int = 500

class VendorNotFoundException(VendorRiskException):
    error_code = "VENDOR_NOT_FOUND"
    http_status = 404

class AgentException(VendorRiskException):
    error_code = "AGENT_FAILURE"
    http_status = 500

class FileValidationException(VendorRiskException):
    error_code = "INVALID_FILE"
    http_status = 400

class DuplicateVendorException(VendorRiskException):
    error_code = "VENDOR_ALREADY_EXISTS"
    http_status = 409
```

---

## Required Test Cases
```
tests/unit/test_orchestrator.py

✅ test_score_vendor_runs_financial_and_cyber_in_parallel
✅ test_failed_agent_added_to_failed_agents_not_raised
✅ test_retry_called_once_on_agent_exception
✅ test_generate_report_routes_to_report_agent_only
✅ test_result_always_returned_even_if_all_agents_fail
```

---

## Validation Rules
```
✅ SCORE_VENDOR must use asyncio.gather — not sequential await calls
✅ execute() must NEVER raise any exception — catch all
✅ failed_agents is empty list when all succeed (never None)
✅ duration_ms measured from start of execute() to return
✅ results dict keys: "financial" | "cyber" | "contract" | "report"
```

---

## Coding Standards
- PEP 8 · black (line-length 88) · mypy --strict
- `snake_case` functions · `PascalCase` classes · `UPPER_SNAKE_CASE` constants
- No bare `except:` · No `print()` · No hardcoded values
- All imports at top of file
- `logging.getLogger(__name__)` — never print()

---

## Definition of Done
- [ ] `orchestrator.py` created with full implementation
- [ ] `exceptions.py` created with all 5 exception classes
- [ ] All 5 test cases pass
- [ ] `asyncio.gather` verified in SCORE_VENDOR path
- [ ] `flake8`, `black --check`, `mypy --strict` all clean
