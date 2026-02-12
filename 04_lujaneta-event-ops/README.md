# La Lujaneta – Pilgrimage Registration & Operations System

![Status](https://img.shields.io/badge/Status-Production%20Ready-success)
![Version](https://img.shields.io/badge/Version-v7.0-blue)
![Security](https://img.shields.io/badge/Security-RLS%20Protected-red)
![Stack](https://img.shields.io/badge/Tech-Supabase%20%7C%20JS%20Vanilla%20%7C%20PostgreSQL-3ecf8e)

La Lujaneta is a pilgrimage group managing 100+ participants per event.
This system was built to improve operational control, reduce manual errors, and accelerate on-site check-in during large-scale pilgrimages.

The objective is not only registration management, but controlled validation of attendance, payment auditing, kit distribution, and behavioral risk tracking across events.

The system is designed with operational reliability, auditability, and staff safety as primary principles.

Operational Flow
1. Participant Registration

Participants complete a mobile-first registration form providing:

Personal identification (DNI / document number)

Emergency contact details

Medical conditions / allergies

Physical activity habits

Payment proof upload

The system performs identity resolution against historical participant records to prevent duplicate profiles and preserve multi-year history.

Payment receipts are securely stored and linked via UUID in Supabase Storage.

2. Administrative Verification (Back Office)

Authorized staff members authenticate using Supabase Authentication (email + password).

Without valid session authentication, no administrative interface is accessible.

Within the Operations Dashboard:

New registrations are reviewed.

Payment receipts are visually audited.

Registrations are either Approved or Rejected.

Once approved, the system generates and sends a unique QR code to the participant’s registered email.

Access control is enforced both at the UI level and at the database level through Row Level Security (RLS) policies.

Public users can INSERT registration data only.
Only authenticated staff can SELECT or UPDATE operational data.

3. Field Check-In & Kit Distribution

During the pilgrimage event, authorized staff log in to the system and access the Scanner module.

The Scanner performs the following validation pipeline:

Identity existence check

Event registration verification

Payment approval status validation

Duplicate kit prevention check

Behavioral risk flag detection

Medical condition visibility alert

If all checks pass, staff can confirm kit delivery with a single action.

The system prevents double scanning and duplicate kit delivery by validating the current registration state before allowing confirmation.

Field Reliability Features

The Scanner module is designed for real-world operational constraints:

Hybrid validation input:

QR camera scanning

Manual DNI fallback (in case of damaged phones, battery issues, or scanning failure)

Anti-freeze camera lifecycle management:
Prevents mobile browser lockups by automatically controlling camera stop/start behavior after scan events.

This ensures continued usability under high participant throughput.

Behavioral Risk Management

Staff can mark a participant as flagged (problematic behavior, prior incidents, etc.).

This flag:

Persists across events and years

Triggers immediate alert visibility during future interactions

Supports staff safety and operational control

Enables reservation of admission rights when necessary

Behavioral data is stored at participant level, not per event, ensuring long-term traceability.

System Architecture
Frontend

Vanilla JavaScript (ES6+)

No frameworks, no build step

Static deployment

Optimized for low overhead and fast load times

Backend

Supabase (Authentication, PostgreSQL, Storage)

Serverless architecture

No infrastructure management required

Database

PostgreSQL 15 with:

Relational separation of participants and registrations

Foreign key constraints

ENUM-based status control

Strong data integrity enforcement

Security

Supabase Authentication for staff access

Strict session validation on protected files (admin.html, scanner.html)

Row Level Security policies enforcing:

Public INSERT-only access

Authenticated staff SELECT/UPDATE permissions

Role-based UI behavior

Access control is enforced at the database level, not only through frontend logic.

Data Model Overview

participants

id

doc_number

full_name

medical_notes

is_flagged

flag_notes

registrations

id

participant_id

event_id

payment_status

kit_status

checked_in

payments

id

registration_id

proof_url

amount

status

The separation between Participant and Registration enables:

Multi-year event tracking

Financial audit traceability

Persistent behavioral flags

Clean relational design

Operational Risk Mitigation

The system explicitly mitigates the following risks:

Duplicate participant profiles → identity resolution by document number

Duplicate kit delivery → registration state validation

Unauthorized staff actions → authentication + RLS enforcement

Aggressive or conflictive participants → persistent behavioral flag

Scanner failure → manual DNI fallback

Mobile browser freezing → controlled camera lifecycle management

Operational control is prioritized over feature density.

Deployment Model

The application is statically deployed (Netlify / GitHub Pages).
Backend services are fully managed (Supabase).

This architecture:

Minimizes operational maintenance

Eliminates infrastructure management

Scales with managed backend services

Reduces operational cost overhead

Design Philosophy

This system was built with an operational mindset:

Reliability over complexity

Control over automation

Database-enforced security over UI-only restrictions

Explicit risk mitigation over reactive fixes

The objective is structured event control, not generic form handling.

## 🔮 Future Roadmap

* **Offline Mode:** Implement Service Workers (PWA) to allow the scanner to cache database subsets and function without internet connectivity.
* **Metrics Dashboard:** Advanced data visualization for "Peak Arrival Times" and revenue forecasting.

---

<p align="center">
  Built by <strong>bandres-ops</strong>
</p>




