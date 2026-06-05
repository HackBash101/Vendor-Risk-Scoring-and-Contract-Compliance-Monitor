PRAGMA foreign_keys = ON;

CREATE TABLE vendors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor_code TEXT NOT NULL UNIQUE,
  legal_name TEXT NOT NULL,
  display_name TEXT NOT NULL,
  primary_industry TEXT NOT NULL CHECK (primary_industry IN ('banking', 'healthcare', 'fintech', 'retail')),
  headquarters_country TEXT NOT NULL DEFAULT 'US',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'monitoring', 'paused', 'terminated')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_vendors_industry_status
  ON vendors(primary_industry, status);

CREATE TABLE contracts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor_id INTEGER NOT NULL,
  contract_number TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  business_unit TEXT NOT NULL,
  owner_name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  renewal_type TEXT NOT NULL CHECK (renewal_type IN ('fixed', 'auto', 'evergreen')),
  auto_renew INTEGER NOT NULL DEFAULT 0 CHECK (auto_renew IN (0, 1)),
  renewal_notice_days INTEGER NOT NULL DEFAULT 60 CHECK (renewal_notice_days BETWEEN 0 AND 365),
  currency_code TEXT NOT NULL DEFAULT 'USD' CHECK (length(currency_code) = 3),
  contract_value_cents INTEGER NOT NULL CHECK (contract_value_cents BETWEEN 5000000 AND 500000000),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'at_risk', 'expired', 'terminated')),
  risk_review_due_date TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE CASCADE
);

CREATE INDEX idx_contracts_vendor_end_date
  ON contracts(vendor_id, end_date);

CREATE INDEX idx_contracts_status_risk_review_due
  ON contracts(status, risk_review_due_date);

CREATE TABLE contract_obligations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  obligation_code TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('sla', 'security', 'delivery', 'billing', 'reporting', 'legal')),
  obligation_type TEXT NOT NULL,
  description TEXT NOT NULL,
  target_value REAL,
  target_unit TEXT,
  threshold_operator TEXT CHECK (threshold_operator IN ('<=', '<', '=', '>=', '>')),
  criticality TEXT NOT NULL CHECK (criticality IN ('low', 'medium', 'high', 'critical')),
  due_date TEXT,
  recurrence TEXT CHECK (recurrence IN ('one_time', 'monthly', 'quarterly', 'annual', 'event_based')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'met', 'at_risk', 'breached', 'waived')),
  last_evaluated_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE,
  UNIQUE (contract_id, obligation_code)
);

CREATE INDEX idx_obligations_contract_status
  ON contract_obligations(contract_id, status);

CREATE INDEX idx_obligations_due_status
  ON contract_obligations(status, due_date);

CREATE TABLE risk_signals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor_id INTEGER NOT NULL,
  contract_id INTEGER,
  dimension TEXT NOT NULL CHECK (dimension IN ('financial', 'cyber', 'compliance')),
  signal_type TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  impact_points INTEGER NOT NULL DEFAULT 0 CHECK (impact_points BETWEEN 0 AND 100),
  observed_at TEXT NOT NULL,
  resolved_at TEXT,
  source TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE CASCADE,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE SET NULL
);

CREATE INDEX idx_risk_signals_vendor_dimension_date
  ON risk_signals(vendor_id, dimension, observed_at DESC);

CREATE INDEX idx_risk_signals_dimension_severity
  ON risk_signals(dimension, severity, observed_at DESC);

CREATE INDEX idx_risk_signals_contract
  ON risk_signals(contract_id, observed_at DESC);

CREATE TABLE sla_breaches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  obligation_id INTEGER,
  breach_code TEXT NOT NULL UNIQUE,
  breach_type TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'resolved', 'waived')),
  detected_at TEXT NOT NULL,
  first_seen_at TEXT NOT NULL,
  resolved_at TEXT,
  description TEXT NOT NULL,
  evidence_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE,
  FOREIGN KEY (obligation_id) REFERENCES contract_obligations(id) ON DELETE SET NULL
);

CREATE INDEX idx_sla_breaches_contract_status
  ON sla_breaches(contract_id, status, detected_at DESC);

CREATE INDEX idx_sla_breaches_obligation
  ON sla_breaches(obligation_id, status);

CREATE TABLE risk_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor_id INTEGER NOT NULL,
  contract_id INTEGER,
  scored_at TEXT NOT NULL,
  financial_score INTEGER NOT NULL CHECK (financial_score BETWEEN 0 AND 100),
  cyber_score INTEGER NOT NULL CHECK (cyber_score BETWEEN 0 AND 100),
  compliance_score INTEGER NOT NULL CHECK (compliance_score BETWEEN 0 AND 100),
  overall_score INTEGER NOT NULL CHECK (overall_score BETWEEN 0 AND 100),
  risk_level TEXT NOT NULL CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  score_version TEXT NOT NULL DEFAULT 'v1',
  explanation_json TEXT NOT NULL DEFAULT '{}',
  model_name TEXT NOT NULL DEFAULT 'gpt-4o-mini',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE CASCADE,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE SET NULL
);

CREATE INDEX idx_risk_scores_vendor_scored_at
  ON risk_scores(vendor_id, scored_at DESC);

CREATE INDEX idx_risk_scores_vendor_risk_level
  ON risk_scores(vendor_id, risk_level, scored_at DESC);

CREATE TABLE ai_analysis_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  analysis_type TEXT NOT NULL CHECK (analysis_type IN ('risk_scoring', 'sla_breach_detection', 'obligation_summary', 'vendor_risk_report')),
  vendor_id INTEGER,
  contract_id INTEGER,
  status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
  prompt_version TEXT NOT NULL,
  model_name TEXT NOT NULL DEFAULT 'gpt-4o-mini',
  input_json TEXT NOT NULL,
  output_json TEXT,
  error_message TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE SET NULL,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE SET NULL
);

CREATE INDEX idx_ai_runs_type_status_created
  ON ai_analysis_runs(analysis_type, status, created_at DESC);

CREATE INDEX idx_ai_runs_vendor_contract
  ON ai_analysis_runs(vendor_id, contract_id, created_at DESC);

CREATE TABLE alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor_id INTEGER NOT NULL,
  contract_id INTEGER,
  alert_type TEXT NOT NULL CHECK (alert_type IN ('risk_threshold', 'sla_breach', 'renewal_due', 'cyber_exposure', 'financial_deterioration')),
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'closed')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  source_run_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  acknowledged_at TEXT,
  closed_at TEXT,
  FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE CASCADE,
  FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE SET NULL,
  FOREIGN KEY (source_run_id) REFERENCES ai_analysis_runs(id) ON DELETE SET NULL
);

CREATE INDEX idx_alerts_vendor_status
  ON alerts(vendor_id, status, created_at DESC);

CREATE INDEX idx_alerts_type_severity
  ON alerts(alert_type, severity, created_at DESC);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_type TEXT NOT NULL DEFAULT 'system' CHECK (actor_type IN ('system', 'ai', 'api', 'ui')),
  actor_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  request_id TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_audit_log_entity_created
  ON audit_log(entity_type, entity_id, created_at DESC);

CREATE INDEX idx_audit_log_request_id
  ON audit_log(request_id, created_at DESC);
