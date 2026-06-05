# AGT-02 — Contract Parsing Agent
> **ID:** AGT-02 | **Owner:** Dev 1 | **When:** Hour 2–3
> **File:** `backend/agents/contract_parsing_agent.py`
> **Layer:** Document Intelligence | **Standard:** IACCM · GDPR Article 28 · ISO/IEC 19510

---

## Purpose
Reads vendor PDF contracts using GPT-4o and extracts every SLA obligation,
penalty clause, and GDPR Article 28 compliance term into structured database
records. The core value prop — humans no longer need to read contracts manually.

---

## Architecture Position
```
POST /vendors/{id}/parse-contract
           │
           ▼
    AGT-01 Orchestrator
           │
           ▼
  ┌────────────────────┐
  │  CONTRACT PARSING  │  ← You are here
  │     AGENT AGT-02   │
  └────────────────────┘
           │  saves to
           ▼
      sla_records table
```

---

## Codex Prompt

```
Goal:
Build the Contract Parsing Agent that extracts SLA obligations and GDPR Art.28
terms from vendor PDF contracts using GPT-4o.

Context:
  @AGENTS.md
  @backend/models/models.py
  @backend/services/openai_client.py
  @backend/exceptions.py

File to create:
  backend/agents/contract_parsing_agent.py

Step 1 — Define dataclasses:

  @dataclass
  class ContractParsingInput:
      vendor_id: int
      pdf_path:  str      # validated temp path — already confirmed to exist
      filename:  str      # sanitised filename for audit log only

  @dataclass
  class SLAObligation:
      obligation_id:    str         # e.g. "SLA-001" — must be unique per contract
      category:         str         # uptime|response_time|resolution_time|delivery|support
      metric_name:      str         # e.g. "uptime_percent", "p1_response_hours"
      threshold_value:  float       # must be > 0
      threshold_unit:   str         # percent|hours|minutes|days
      severity:         str         # P1|P2|P3|standard
      penalty_type:     str         # credit|termination|financial|none
      penalty_formula:  str | None  # e.g. "5% monthly fee credit"

  @dataclass
  class GDPRTerms:
      breach_notification_hours: int | None   # GDPR Art.33 — must be <= 72
      data_retention_days:       int | None   # must be specified
      deletion_on_termination:   bool         # GDPR Art.28(3)(g) — must be True
      sub_processors_allowed:    bool

  @dataclass
  class ContractParsingOutput:
      vendor_id:         int
      obligations:       list[SLAObligation]
      gdpr_terms:        GDPRTerms
      gdpr_compliant:    bool           # True only if apply_gdpr_checks returns []
      risk_flags:        list[str]      # standardised flag codes
      pages_processed:   int
      confidence:        str            # High|Medium|Low
      parsed_at:         datetime

Step 2 — Implement validate_pdf(pdf_path: str) -> None:
  - Raise FileValidationException if file does not exist
  - Open file in binary mode, read first 4 bytes
  - Raise FileValidationException("Not a valid PDF file") if bytes != b'%PDF'
  - Get file size in bytes
  - max_bytes = int(os.getenv("MAX_UPLOAD_SIZE_MB", "5")) * 1024 * 1024
  - Raise FileValidationException("File exceeds 5MB limit") if size > max_bytes

Step 3 — Implement extract_text(pdf_path: str) -> tuple[str, int]:
  - from PyPDF2 import PdfReader
  - reader = PdfReader(pdf_path)
  - Extract text from all pages: "\n".join(page.extract_text() or "" for page in reader.pages)
  - Return (full_text, len(reader.pages))
  - Wrap in try/except Exception — raise FileValidationException("Unreadable PDF") on error

Step 4 — Implement chunk_text(text: str, max_chars: int = 12000) -> list[str]:
  - Split text into chunks of max_chars characters
  - Apply 500-char overlap between chunks (prevents SLA clause from being split)
  - Return list of non-empty string chunks

Step 5 — Implement call_gpt4o(chunk: str) -> dict:
  Use this EXACT system prompt — do not change it:
  ---
  You are a specialist contract analyst trained in IACCM standards and
  GDPR Article 28 compliance. Extract ALL SLA obligations and GDPR terms
  from the contract text provided.
  Return ONLY valid JSON. No preamble, no markdown fences, no explanation.
  Schema:
  {
    "sla_obligations": [{
      "obligation_id": "SLA-001",
      "category": "uptime|response_time|resolution_time|delivery|support",
      "metric_name": "string",
      "threshold_value": 99.9,
      "threshold_unit": "percent|hours|minutes|days",
      "severity": "P1|P2|P3|standard",
      "penalty_type": "credit|termination|financial|none",
      "penalty_formula": "string or null"
    }],
    "gdpr_terms": {
      "breach_notification_hours": 72,
      "data_retention_days": 365,
      "deletion_on_termination": true,
      "sub_processors_allowed": false
    },
    "risk_flags": ["MISSING_UPTIME_SLA", "NO_PENALTY_CLAUSE"]
  }
  ---
  - Call openai GPT-4o with system prompt above + chunk as user message
  - Parse JSON from response.choices[0].message.content.strip()
  - If JSON parsing fails: retry ONCE with same chunk
  - If retry also fails: return empty structure, confidence = "Low"

Step 6 — Implement merge_results(results: list[dict]) -> dict:
  - Collect all sla_obligations from every chunk result
  - Deduplicate by obligation_id — keep first occurrence only
  - Merge gdpr_terms: for each field use first non-null value across chunks
  - Merge risk_flags: union of all flags, deduplicated, order preserved
  - Return single merged dict

Step 7 — Implement apply_gdpr_checks(gdpr_terms: GDPRTerms) -> list[str]:
  flags = []
  if gdpr_terms.breach_notification_hours is None or gdpr_terms.breach_notification_hours > 72:
      flags.append("GDPR_BREACH_NOTIFY_EXCEEDS_72H")
  if gdpr_terms.deletion_on_termination is False:
      flags.append("NO_DELETION_ON_TERMINATION")
  if gdpr_terms.data_retention_days is None:
      flags.append("MISSING_RETENTION_PERIOD")
  return flags

Step 8 — Implement validate_obligations(raw: list[dict]) -> list[SLAObligation]:
  For each obligation dict:
  - Skip if threshold_value is None or <= 0
  - Skip if threshold_unit not in ["percent","hours","minutes","days"]
  - Skip if severity not in ["P1","P2","P3","standard"]
  - Build SLAObligation from valid fields
  Return list of valid obligations only

Step 9 — Implement parse_contract(
    input: ContractParsingInput, db: Session
) -> ContractParsingOutput:
  try:
    1. validate_pdf(input.pdf_path)
    2. text, pages = extract_text(input.pdf_path)
    3. chunks = chunk_text(text)
    4. raw_results = [call_gpt4o(chunk) for chunk in chunks]
    5. merged = merge_results(raw_results)
    6. obligations = validate_obligations(merged["sla_obligations"])
    7. gdpr_terms = GDPRTerms(**merged.get("gdpr_terms", {}))
    8. gdpr_flags = apply_gdpr_checks(gdpr_terms)
    9. risk_flags = list(set(merged.get("risk_flags", []) + gdpr_flags))
    10. If no obligation with category=="uptime" in obligations:
            risk_flags.append("MISSING_UPTIME_SLA")
    11. gdpr_compliant = len(gdpr_flags) == 0
    12. For each obligation: save SLARecord to sla_records table in DB
    13. Build and return ContractParsingOutput
  finally:
    # THIS BLOCK MUST ALWAYS RUN — on success AND on exception
    if os.path.exists(input.pdf_path):
        os.remove(input.pdf_path)

Constraints:
  - Temp file ALWAYS deleted in finally block — no exceptions
  - call_gpt4o() independently mockable — no direct openai import in parse_contract
  - validate_pdf() independently mockable
  - Type hints on all signatures
  - Google-style docstrings on all public functions
  - No print() — use logging.getLogger(__name__)
  - Max function length 50 lines

Done-when:
  - parse_contract() extracts obligations, runs GDPR checks, saves to DB
  - test_temp_file_deleted_on_success passes
  - test_temp_file_deleted_on_exception passes
  - All 9 required test cases pass
  - flake8 and mypy clean
```

---

## Interface Contracts

### Inputs
```python
@dataclass
class ContractParsingInput:
    vendor_id: int
    pdf_path:  str
    filename:  str
```

### Output
```python
@dataclass
class ContractParsingOutput:
    vendor_id:       int
    obligations:     list[SLAObligation]
    gdpr_terms:      GDPRTerms
    gdpr_compliant:  bool
    risk_flags:      list[str]
    pages_processed: int
    confidence:      str      # "High"|"Medium"|"Low"
    parsed_at:       datetime
```

---

## GPT-4o Extraction Schema
```json
{
  "sla_obligations": [{
    "obligation_id": "SLA-001",
    "category": "uptime",
    "metric_name": "uptime_percent",
    "threshold_value": 99.9,
    "threshold_unit": "percent",
    "severity": "P1",
    "penalty_type": "credit",
    "penalty_formula": "5% monthly fee credit per 0.1% below threshold"
  }],
  "gdpr_terms": {
    "breach_notification_hours": 72,
    "data_retention_days": 365,
    "deletion_on_termination": true,
    "sub_processors_allowed": false
  },
  "risk_flags": []
}
```

---

## GDPR Article 28 Compliance Checks
| Check | Rule | Flag if Violated |
|---|---|---|
| Breach Notification | Must be ≤ 72 hours (GDPR Art.33) | `GDPR_BREACH_NOTIFY_EXCEEDS_72H` |
| Data Deletion | Must be True on termination (Art.28(3)(g)) | `NO_DELETION_ON_TERMINATION` |
| Retention Period | Must be explicitly stated | `MISSING_RETENTION_PERIOD` |
| Uptime SLA | Must be present in any contract | `MISSING_UPTIME_SLA` |

---

## Validation Rules
```
✅ PDF magic bytes: first 4 bytes must be b'%PDF'
✅ File size: must be <= MAX_UPLOAD_SIZE_MB (env var, default 5)
✅ threshold_value: must be > 0 — skip obligations with 0 or negative
✅ threshold_unit: must be one of percent|hours|minutes|days
✅ severity: must be one of P1|P2|P3|standard
✅ obligation_ids: must be unique — deduplicate by keeping first
✅ gdpr_compliant: True ONLY if all 3 GDPR checks pass
✅ Temp file: ALWAYS deleted in finally block
✅ GPT-4o failure: retry once, then return empty + confidence=Low
```

---

## Required Test Cases
```
tests/unit/test_contract_parsing_agent.py

✅ test_valid_pdf_returns_obligations_list
✅ test_non_pdf_magic_bytes_raises_file_validation_exception
✅ test_file_over_5mb_raises_file_validation_exception
✅ test_breach_notification_over_72h_adds_gdpr_flag
✅ test_missing_uptime_sla_adds_risk_flag
✅ test_gdpr_compliant_false_when_art28_check_fails
✅ test_duplicate_obligation_ids_deduplicated
✅ test_temp_file_deleted_on_success
✅ test_temp_file_deleted_on_exception
```

---

## Definition of Done
- [ ] `contract_parsing_agent.py` created with all 9 functions
- [ ] All 9 test cases pass
- [ ] GDPR checks produce correct flags
- [ ] Temp file deleted on both success and failure
- [ ] `flake8`, `black --check`, `mypy --strict` all clean
