# AGT-04 — Cybersecurity Posture Agent
> **ID:** AGT-04 | **Owner:** Dev 2 | **When:** Hour 3
> **File:** `backend/agents/cybersecurity_posture_agent.py`
> **Layer:** Core Intelligence | **Standard:** NIST CSF 2.0 · CVSS v3.1 · CIS Controls v8 · OWASP

---

## Purpose
Assesses vendor cybersecurity hygiene using NIST Cybersecurity Framework 2.0.
Scores SSL configuration, HTTP security headers, known CVEs (CVSS v3.1), and
breach history to produce a normalised Cyber Risk Score (0–100).

---

## Architecture Position
```
AGT-01 Orchestrator
        │
        ▼ (parallel with AGT-03)
┌───────────────────────┐
│  CYBERSECURITY        │  ← You are here
│  POSTURE AGENT AGT-04 │
└───────────────────────┘
        │  saves to
        ▼
   cyber_scores table
```

---

## NIST CSF 2.0 Function Mapping
```
┌─────────────────┬──────────────────────────────┬────────┐
│ NIST Function   │ Signal Measured               │ Weight │
├─────────────────┼──────────────────────────────┼────────┤
│ IDENTIFY (ID)   │ Open sensitive ports          │  20%   │
│ PROTECT (PR)    │ SSL validity + security hdrs  │  25%   │
│ DETECT (DE)     │ CVEs in last 90 days          │  25%   │
│ RESPOND (RS)    │ Breach history proxy          │  15%   │
│ RECOVER (RC)    │ SSL + headers combined        │  15%   │
└─────────────────┴──────────────────────────────┴────────┘
```

---

## CVSS v3.1 Penalty Bands
```
CRITICAL (9.0–10.0)  →  -25 points
HIGH     (7.0–8.9)   →  -15 points
MEDIUM   (4.0–6.9)   →  -8 points
LOW      (0.1–3.9)   →  -3 points
```

---

## Codex Prompt

```
Goal:
Implement the Cybersecurity Posture Agent aligned to NIST CSF 2.0 and CVSS v3.1
to make ALL tests in tests/unit/test_cybersecurity_posture_agent.py pass.

Context:
  @AGENTS.md
  @backend/models/models.py
  @backend/exceptions.py
  @tests/unit/test_cybersecurity_posture_agent.py  ← tests exist, make them pass

File to create:
  backend/agents/cybersecurity_posture_agent.py

Step 1 — Define constants at module level:

  CVSS_PENALTY: dict[str, int] = {
      "CRITICAL": 25, "HIGH": 15, "MEDIUM": 8, "LOW": 3,
  }
  SENSITIVE_PORTS: list[int] = [22, 3389, 5432, 1433, 27017]
  REQUIRED_SECURITY_HEADERS: dict[str, int] = {
      "Strict-Transport-Security": 20,
      "Content-Security-Policy":   20,
      "X-Frame-Options":           15,
      "X-Content-Type-Options":    15,
      "Referrer-Policy":           15,
      "Permissions-Policy":        15,
  }

Step 2 — Define dataclasses:

  @dataclass
  class CVERecord:
      cve_id:     str    # e.g. "CVE-2024-1234"
      cvss_score: float  # 0.0–10.0
      severity:   str    # CRITICAL|HIGH|MEDIUM|LOW
      days_ago:   int    # days since CVE was published

  @dataclass
  class CyberPostureInput:
      vendor_id:   int
      vendor_name: str
      domain:      str

  @dataclass
  class CyberPostureOutput:
      vendor_id:              int
      cyber_score:            int            # 0–100 clamped
      ssl_valid:              bool
      ssl_grade:              str            # A+|A|B|C|D|F|UNKNOWN
      security_headers_score: int            # 0–100
      open_sensitive_ports:   list[int]
      cve_count_12m:          int
      critical_cve_count:     int
      breach_history:         bool
      nist_csf_scores:        dict           # all 5 functions
      risk_flags:             list[str]
      confidence:             str            # High|Medium|Low
      scanned_at:             datetime

Step 3 — Implement check_ssl(domain: str) -> tuple[bool, str]:
  Use ssl + socket stdlib only — no external dependencies.
  Try to connect to domain:443 with timeout=5
  Grade logic:
    TLS 1.3 + valid cert + not expired → ("True", "A+")
    TLS 1.2 + valid → (True, "A")
    Valid but other version → (True, "B")
    Expired cert → (False, "F")
    Connection refused/any exception → (False, "UNKNOWN")
  NOTE: Mock this in tests — makes real network calls.

Step 4 — Implement check_security_headers(domain: str) -> int:
  Make HEAD request to https://{domain} with timeout=5 using requests
  For each header in REQUIRED_SECURITY_HEADERS:
    if present in response.headers: add weight to total
  Return total (0–100)
  Return 50 (neutral/unknown) on any exception

Step 5 — Implement fetch_cve_data(vendor_name: str) -> list[CVERecord]:
  # Deterministic mock seeded by vendor name hash
  # TODO: replace with NVD API
  seed = abs(hash(vendor_name)) % 100
  if seed < 30:    return []
  elif seed < 70:  return [CVERecord(f"CVE-2024-{seed:04d}", 6.5, "MEDIUM", 180)]
  elif seed < 90:  return [CVERecord(f"CVE-2024-{seed:04d}", 8.2, "HIGH",   45)]
  else:            return [CVERecord(f"CVE-2024-{seed:04d}", 9.8, "CRITICAL", 30)]

Step 6 — Implement check_breach_history(domain: str) -> bool:
  # Mock: ~20% of domains return True
  # TODO: replace with HaveIBeenPwned Enterprise API
  return abs(hash(domain)) % 5 == 0

Step 7 — Implement simulate_port_scan(domain: str) -> list[int]:
  # Mock: 80% clean, 10% SSH, 10% RDP
  # TODO: replace with authorised scanner
  seed = abs(hash(domain)) % 10
  if seed == 0: return [22]
  if seed == 1: return [3389]
  return []

Step 8 — Implement compute_nist_csf_scores(
    ssl_valid, ssl_grade, headers_score, cves, breach_history, open_ports
) -> dict[str, int]:
  recent_cves = [c for c in cves if c.days_ago <= 90]
  return {
      "IDENTIFY": max(0, min(100, 100 - len(open_ports) * 15)),
      "PROTECT":  max(0, min(100, int(headers_score * 0.5) + (50 if ssl_valid else 0))),
      "DETECT":   max(0, min(100, 100 - len(recent_cves) * 20)),
      "RESPOND":  85 if not breach_history else 50,
      "RECOVER":  90 if ssl_valid and headers_score >= 60 else 60,
  }

Step 9 — Implement compute_base_cyber_score(nist_scores: dict) -> int:
  weighted = (
      nist_scores["IDENTIFY"] * 0.20 +
      nist_scores["PROTECT"]  * 0.25 +
      nist_scores["DETECT"]   * 0.25 +
      nist_scores["RESPOND"]  * 0.15 +
      nist_scores["RECOVER"]  * 0.15
  )
  return max(0, min(100, int(round(weighted))))

Step 10 — Implement apply_cyber_validation_rules(
    score, ssl_valid, ssl_grade, cves, breach_history, open_ports, headers_score
) -> tuple[int, list[str]]:
  risk_flags = []
  # Rule 1: Invalid SSL → cap at 40
  if not ssl_valid:
      score = min(score, 40)
      risk_flags.append("SSL_INVALID_OR_EXPIRED")
  # Rule 2: Breach history → -20
  if breach_history:
      score -= 20
      risk_flags.append("ACTIVE_BREACH_HISTORY")
  # Rule 3: Critical CVE last 90 days → cap at 50
  if any(c.severity == "CRITICAL" and c.days_ago <= 90 for c in cves):
      score = min(score, 50)
      risk_flags.append("CRITICAL_CVE_LAST_90_DAYS")
  # Rule 4: Exposed ports → -10 each
  for port in open_ports:
      score -= 10
      risk_flags.append(f"EXPOSED_PORT_{port}")
  # Rule 5: Weak SSL → -20
  if ssl_grade in ["D","F"]:
      score -= 20
      risk_flags.append("WEAK_SSL_GRADE")
  # Rule 6: Missing headers → -10
  if headers_score < 50:
      score -= 10
      risk_flags.append("MISSING_SECURITY_HEADERS")
  return (max(0, min(100, score)), risk_flags)

Step 11 — Implement score_vendor_cyber(
    input: CyberPostureInput, db: Session
) -> CyberPostureOutput:
  1. Query vendor — raise VendorNotFoundException if not found
  2. Collect: ssl_valid, ssl_grade = check_ssl(input.domain)
  3.          headers_score = check_security_headers(input.domain)
  4.          cves = fetch_cve_data(input.vendor_name)
  5.          breach_history = check_breach_history(input.domain)
  6.          open_ports = simulate_port_scan(input.domain)
  7. nist_scores = compute_nist_csf_scores(...)
  8. base_score = compute_base_cyber_score(nist_scores)
  9. final_score, risk_flags = apply_cyber_validation_rules(...)
  10. confidence = "High" if ssl_grade != "UNKNOWN" and headers_score != 50 else "Medium"
  11. Save CyberScore record to cyber_scores table
  12. Return CyberPostureOutput

Constraints:
  - cyber_score ALWAYS clamped to [0, 100]
  - nist_csf_scores dict ALWAYS contains all 5 keys
  - check_ssl and check_security_headers independently mockable
  - All 6 validation rules applied in exact order above
  - Type hints on ALL signatures
  - Do NOT modify any test file

Done-when:
  All 12 tests in tests/unit/test_cybersecurity_posture_agent.py pass
  pytest shows 0 failures, 0 errors
```

---

## Interface Contracts

### Input
```python
@dataclass
class CyberPostureInput:
    vendor_id:   int
    vendor_name: str
    domain:      str
```

### Output
```python
@dataclass
class CyberPostureOutput:
    vendor_id:              int
    cyber_score:            int        # 0–100 clamped
    ssl_valid:              bool
    ssl_grade:              str        # A+|A|B|C|D|F|UNKNOWN
    security_headers_score: int        # 0–100
    open_sensitive_ports:   list[int]
    cve_count_12m:          int
    critical_cve_count:     int
    breach_history:         bool
    nist_csf_scores:        dict       # 5 NIST function scores
    risk_flags:             list[str]
    confidence:             str        # High|Medium|Low
    scanned_at:             datetime
```

---

## Validation Rules (Priority Order)
| Rule | Condition | Action |
|---|---|---|
| 1. SSL invalid | `not ssl_valid` | `score = min(score, 40)` + flag |
| 2. Breach history | `breach_history == True` | `score -= 20` + flag |
| 3. Critical CVE | CRITICAL + days_ago ≤ 90 | `score = min(score, 50)` + flag |
| 4. Exposed ports | any in `open_sensitive_ports` | `-10 per port` + flag per port |
| 5. Weak SSL | grade in D or F | `score -= 20` + flag |
| 6. Headers missing | `headers_score < 50` | `score -= 10` + flag |
| Final | Always | `max(0, min(100, score))` |

---

## Security Headers Scoring (CIS Controls v8)
| Header | Weight |
|---|---|
| Strict-Transport-Security | 20 |
| Content-Security-Policy | 20 |
| X-Frame-Options | 15 |
| X-Content-Type-Options | 15 |
| Referrer-Policy | 15 |
| Permissions-Policy | 15 |

---

## Required Test Cases
```
tests/unit/test_cybersecurity_posture_agent.py

✅ test_score_is_integer_between_0_and_100
✅ test_expired_ssl_caps_cyber_score_at_maximum_40
✅ test_breach_history_true_deducts_20_points
✅ test_critical_cve_in_90_days_caps_score_at_50
✅ test_open_sensitive_port_deducts_10_points_per_port
✅ test_ssl_grade_F_deducts_20_points
✅ test_missing_critical_headers_deducts_10_points
✅ test_nist_csf_output_has_all_five_functions
✅ test_each_nist_csf_score_is_between_0_and_100
✅ test_unreachable_domain_returns_score_50_with_risk_flag
✅ test_output_contains_all_required_fields
✅ test_result_is_saved_to_cyber_scores_table
```

---

## Definition of Done
- [ ] `cybersecurity_posture_agent.py` created with all 11 functions
- [ ] All 12 test cases pass with 0 failures
- [ ] All 5 NIST CSF function scores computed and present
- [ ] All 6 validation rules applied in correct order
- [ ] `flake8`, `black --check`, `mypy --strict` all clean
