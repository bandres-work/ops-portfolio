# Automation Incident Post-Mortems

This document captures lessons learned from simulated automation failures.
The goal is to reduce recurrence, improve detection, and shorten recovery time.

---

## INC-001 — Trigger Failure

**What happened**  
A scheduled automation did not execute at the expected time.

**Root cause**  
Trigger configuration was not validated after a schedule update.

**Recovery**  
Automation was manually retried without side effects.

**Preventive action**  
Add execution count monitoring to detect missed runs.

---

## INC-002 — Data Integrity Failure

**What happened**  
Automation received incomplete data and could not proceed.

**Root cause**  
Upstream validation allowed missing required fields.

**Recovery**  
Data was corrected manually and automation reprocessed.

**Preventive action**  
Enforce required field validation before automation intake.

---

## INC-003 — Execution Failure

**What happened**  
Automation failed due to an external API timeout.

**Root cause**  
API rate limits were exceeded during peak usage.

**Recovery**  
Automation was retried after rate limits reset.

**Preventive action**  
Introduce retry delays and rate-limit awareness.

---

## INC-004 — Logic Failure

**What happened**  
Automation completed but created duplicate records.

**Root cause**  
Conditional logic did not handle repeated inputs correctly.

**Recovery**  
Partial rollback removed duplicate records.

**Preventive action**  
Add idempotency checks to prevent duplicates.

---

## INC-005 — Silent Failure

**What happened**  
Automation completed successfully but produced no output.

**Root cause**  
Downstream condition prevented processing without raising errors.

**Recovery**  
Execution aborted and incident logged.

**Preventive action**  
Add minimum output thresholds to detect silent failures.
