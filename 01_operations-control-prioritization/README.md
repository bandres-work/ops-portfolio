# Operations Control & Prioritization System

## Overview
This project presents a structured system to control and prioritize operational requests using explicit decision criteria rather than intuition or ad-hoc judgment.

The system is designed to ensure that limited operational capacity is allocated to the highest-value and highest-risk work first, with all prioritization decisions justified and traceable.

---

## Problem Statement

Operational teams often face multiple incoming requests competing for attention.  
Without a formal prioritization model, work is typically handled based on urgency perception, stakeholder pressure, or recency.

This leads to:
- Reactive execution
- Misallocation of effort
- High-risk work being delayed
- Lack of justification for prioritization decisions

---

## Objective

Design a prioritization system that:
- Makes prioritization decisions explicit
- Reduces subjectivity and bias
- Aligns execution order with impact and risk
- Provides a clear audit trail for why work was prioritized

---

## System Scope

Included:
- Intake of operational requests
- Scoring based on defined criteria
- Priority assignment rules
- Decision documentation

Excluded:
- Task execution details
- Tool-specific implementations
- Resource scheduling optimization

---

## Prioritization Model

Each request is evaluated using three criteria:

- **Impact**: Expected effect on business or operations if the request is completed
- **Urgency**: Time sensitivity and consequences of delay
- **Risk**: Potential negative impact if the request is delayed or handled incorrectly

Each criterion is scored on a 1–5 scale.

---

## Scoring Logic

Total Priority Score = Impact × Urgency × Risk

This multiplicative model ensures that:
- High-risk items are not deprioritized due to low urgency
- High-impact items surface even if not immediately urgent
- Low-value work does not outrank critical work

---

## Priority Classification Rules

Based on the total score, requests are classified as:

- **P1 (Critical)**: Score ≥ 60  
  Immediate attention required. Delays create significant operational or business risk.

- **P2 (High)**: Score 30–59  
  Important work that should be scheduled promptly.

- **P3 (Normal)**: Score 10–29  
  Standard operational work.

- **P4 (Low)**: Score < 10  
  Deferable work with limited impact or risk.

---

## Decision Flow

1. Request is submitted through intake
2. Criteria are scored
3. Priority is calculated automatically
4. Priority is reviewed for anomalies
5. Work is either accepted, deferred, or rejected
6. Decision and justification are recorded

---

## Example Scenario

Request A:
- Impact: 4
- Urgency: 3
- Risk: 4

Score: 4 × 3 × 4 = 48 → **P2 (High)**

This request is prioritized above multiple lower-impact but more urgent requests due to its risk profile.

---

## Outcomes

This system enables:
- Consistent prioritization decisions
- Reduced reactive work
- Clear justification for trade-offs
- Improved operational transparency

---

## Notes

This project focuses on decision logic and system design rather than specific tools or platforms.

