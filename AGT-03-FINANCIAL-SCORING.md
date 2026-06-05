# AGT-03 — Financial Scoring Agent
> **ID:** AGT-03 | **Owner:** Dev 2 | **When:** Hour 2
> **File:** `backend/agents/financial_scoring_agent.py`
> **Layer:** Core Intelligence | **Standard:** Basel III · Altman Z-Score (1968) · NIST SP 800-161

---

## Purpose
Quantifies vendor financial health using the Altman Z-Score model — the same
quantitative model used by banks and credit agencies to predict corporate
financial distress. Produces a normalised Financial Risk Score (0–100).

---

## Architecture Position
```
AGT-01 Orchestrator
        │
        ▼ (parallel with AGT-04)
┌───────────────────────┐
│  FINANCIAL SCORING    │  ← You are here
│     AGENT AGT-03      │
└───────────────────────┘
        │  saves to
        ▼
  financial_scores table
```

---

## Altman Z-Score Model
```
Z' = 0.717(X1) + 0.847(X2) + 3.107(X3) + 0.420(X4) + 0.998(X5)

Inputs (derived from vendor signals):
  X1 = working capital proxy    (from revenue trend)
  X2 = retained earnings proxy  (from debt/equity ratio)
  X3 = EBIT proxy               (from credit rating)
  X4 = equity/debt ratio        (inverse of debt/equity)
  X5 = revenue efficiency       (from payment history score)

Risk Zones:
  Z' >= 2.9          →  Safe Zone     →  score 75–100
  1.23 <= Z' < 2.9   →  Grey Zone     →  score 45–74
  Z' < 1.23          →  Distress Zone →  score 0–44
```

---

## Codex Prompt

```
Goal:
Implement the Financial Scoring Agent using the Altman Z-Score model (Basel III aligned)
to make ALL tests in tests/unit/test_financial_scoring_agent.py pass.

Context:
  @AGENTS.md
  @backend/models/models.py
  @backend/exceptions.py
  @tests/unit/test_financial_scoring_agent.py  ← tests exist, make them pass

File to create:
  backend/agents/financial_scoring_agent.py

Step 1 — Define dataclasses:

  @dataclass
  class FinancialScoringInput:
      vendor_id:    int
      vendor_name:  str
      domain:       str
      category:     str

  @dataclass
  class FinancialScoringOutput:
      vendor_id:         int
      financial_score:   int         # 0–100 integer, ALWAYS clamped
      z_score:           float       # raw Altman Z' value
      risk_zone:         str         # "Safe" | "Grey" | "Distress"
      credit_rating:     str         # "A" | "B" | "C" | "D" | "UNKNOWN"
      revenue_trend:     str         # "Growing" | "Stable" | "Declining"
      distress_signals:  list[str]   # human-readable risk flags
      confidence:        str         # "High" | "Medium" | "Low"
      scored_at:         datetime

Step 2 — Implement fetch_financial_signals(vendor_name: str, domain: str) -> dict:
  # Deterministic mock — same domain always returns same values
  # TODO: replace with Dun & Bradstreet / Experian API
  seed = abs(hash(domain)) % 1000
  return {
      "credit_rating":        ["A","A","B","B","C","D"][seed % 6],
      "revenue_trend":        ["Growing","Stable","Stable","Declining"][seed % 4],
      "debt_equity_ratio":    round(0.5 + (seed % 30) / 10, 2),
      "layoff_signals":       ["Layoffs announced Q3"] if seed % 7 == 0 else [],
      "payment_history_score": 50 + (seed % 50),
      "years_in_business":    1 + (seed % 29),
  }

Step 3 — Implement compute_z_score(signals: dict) -> float:
  """Compute Altman Z' from vendor financial signals.
  Z' = 0.717*X1 + 0.847*X2 + 3.107*X3 + 0.420*X4 + 0.998*X5
  """
  trend   = signals["revenue_trend"]
  rating  = signals["credit_rating"]
  debt_eq = max(signals["debt_equity_ratio"], 0.01)
  pay_scr = signals["payment_history_score"]

  X1 = 0.40 if trend == "Growing" else 0.20 if trend == "Stable" else 0.10
  X2 = max(0.0, min(0.5, 0.30 - (debt_eq * 0.05)))
  X3 = 0.15 if rating in ["A","B"] else 0.08
  X4 = min(5.0, 1.0 / debt_eq)
  X5 = pay_scr / 100.0

  return round(0.717*X1 + 0.847*X2 + 3.107*X3 + 0.420*X4 + 0.998*X5, 4)

Step 4 — Implement normalise_z_to_score(z_prime: float) -> tuple[int, str]:
  """Map Z' to 0–100 score and risk zone string."""
  if z_prime >= 2.9:
      return (min(100, 75 + int((z_prime - 2.9) * 10)), "Safe")
  elif z_prime >= 1.23:
      return (min(74, 45 + int(((z_prime - 1.23) / 1.67) * 29)), "Grey")
  else:
      return (max(0, int((z_prime / 1.23) * 44)), "Distress")

Step 5 — Implement build_distress_signals(signals: dict) -> list[str]:
  flags = []
  if signals["revenue_trend"] == "Declining":
      flags.append("Declining Revenue")
  if signals["debt_equity_ratio"] > 2.0:
      flags.append("High Debt Load")
  if signals["layoff_signals"]:
      flags.append("Recent Layoffs")
  if signals["payment_history_score"] < 60:
      flags.append("Poor Payment History")
  if signals["years_in_business"] < 1:
      flags.append("New Vendor — Limited History")
  return flags

Step 6 — Implement apply_validation_rules(
    score: int, signals: dict, distress_signals: list[str]
) -> int:
  """Enforce hard scoring caps in priority order."""
  # Rule 1: Credit D → hard cap at 30
  if signals.get("credit_rating") == "D":
      score = min(score, 30)
  # Rule 2: 3+ distress signals → cap at 50
  if len(distress_signals) >= 3:
      score = min(score, 50)
  # Rule 3: New vendor penalty
  if signals.get("years_in_business", 99) < 1:
      score = max(0, score - 10)
  # Always clamp
  return max(0, min(100, score))

Step 7 — Implement calculate_confidence(signals: dict) -> str:
  required = [
      "credit_rating","revenue_trend","debt_equity_ratio",
      "layoff_signals","payment_history_score","years_in_business"
  ]
  present = sum(
      1 for k in required
      if signals.get(k) is not None and signals.get(k) != []
  )
  return "High" if present >= 6 else "Medium" if present >= 4 else "Low"

Step 8 — Implement score_vendor_financial(
    input: FinancialScoringInput, db: Session
) -> FinancialScoringOutput:
  1. Query vendor: raise VendorNotFoundException if not found or not active
  2. signals = fetch_financial_signals(input.vendor_name, input.domain)
  3. distress_signals = build_distress_signals(signals)
  4. z_score = compute_z_score(signals)
  5. base_score, risk_zone = normalise_z_to_score(z_score)
  6. final_score = apply_validation_rules(base_score, signals, distress_signals)
  7. confidence = calculate_confidence(signals)
  8. Save FinancialScore record to DB (financial_scores table)
  9. Return FinancialScoringOutput

Constraints:
  - financial_score ALWAYS integer in [0, 100] — hard clamp, no exceptions
  - fetch_financial_signals() must be independently mockable (pure function)
  - All scoring functions pure — no DB or API calls inside them
  - Type hints on ALL signatures
  - Google-style docstrings on all public functions
  - No print() — use logging.getLogger(__name__)
  - Do NOT modify any test file

Done-when:
  All 11 tests in tests/unit/test_financial_scoring_agent.py pass
  pytest shows 0 failures, 0 errors
```

---

## Interface Contracts

### Input
```python
@dataclass
class FinancialScoringInput:
    vendor_id:   int
    vendor_name: str
    domain:      str
    category:    str
```

### Output
```python
@dataclass
class FinancialScoringOutput:
    vendor_id:        int
    financial_score:  int         # 0–100 clamped
    z_score:          float       # raw Altman Z'
    risk_zone:        str         # Safe|Grey|Distress
    credit_rating:    str         # A|B|C|D|UNKNOWN
    revenue_trend:    str         # Growing|Stable|Declining
    distress_signals: list[str]
    confidence:       str         # High|Medium|Low
    scored_at:        datetime
```

---

## Scoring Formula Detail
```python
# Altman Z' coefficients
Z' = 0.717*X1 + 0.847*X2 + 3.107*X3 + 0.420*X4 + 0.998*X5

# Normalisation to 0–100
Z' >= 2.9:   score = min(100, 75 + int((Z' - 2.9) * 10))   # Safe Zone
Z' >= 1.23:  score = 45 + int(((Z' - 1.23) / 1.67) * 29)  # Grey Zone
Z' < 1.23:   score = max(0, int((Z' / 1.23) * 44))          # Distress Zone
```

---

## Validation Rules (Priority Order)
| Rule | Condition | Action |
|---|---|---|
| 1. Credit D cap | `credit_rating == "D"` | `score = min(score, 30)` |
| 2. Distress cap | `len(distress_signals) >= 3` | `score = min(score, 50)` |
| 3. New vendor penalty | `years_in_business < 1` | `score -= 10` |
| 4. Hard clamp | Always | `max(0, min(100, score))` |

---

## Confidence Levels
| Level | Condition |
|---|---|
| High | All 6 signals present and non-null |
| Medium | 4–5 signals present |
| Low | Fewer than 4 signals |

---

## Required Test Cases
```
tests/unit/test_financial_scoring_agent.py

✅ test_score_is_integer_between_0_and_100
✅ test_z_score_above_2_9_returns_safe_zone_score_above_75
✅ test_z_score_below_1_23_returns_distress_zone_score_below_44
✅ test_credit_rating_D_caps_score_at_maximum_30
✅ test_three_distress_signals_caps_score_at_maximum_50
✅ test_vendor_under_1_year_receives_startup_penalty_flag
✅ test_confidence_high_when_all_6_signals_present
✅ test_confidence_low_when_fewer_than_4_signals
✅ test_output_contains_all_required_fields
✅ test_result_saved_to_financial_scores_table
✅ test_unknown_vendor_raises_vendor_not_found
```

---

## Definition of Done
- [ ] `financial_scoring_agent.py` created with all 8 functions
- [ ] All 11 test cases pass with 0 failures
- [ ] Altman Z-Score formula implemented exactly as specified
- [ ] All 4 validation rules enforced in correct priority order
- [ ] `flake8`, `black --check`, `mypy --strict` all clean
