# Pilgrimage Registration & Management System (Phase 1)

## Project Overview
This project automates participant registration and management for a pilgrimage through:

1. Online registration form.  
2. Upload of payment proof.  
3. Manual verification of payment by the operations team.  
4. Automatic generation and email delivery of a unique QR code once payment is confirmed.  
5. QR scanning at the event to mark attendance and kit delivery.  

> Phase 1 focuses on **digital registration, payment, and QR system**. Phase 2 will include physical ID cards, recurring payments tied to participant ID, and a full staff panel.

---

## Database Model (Supabase / PostgreSQL)

### Main Tables

- **participants**  
  Stores participant information.  
  Example fields:  
  - id (PK)  
  - name  
  - document_id  
  - email  
  - phone  
  - medical_conditions  

- **events**  
  Stores event details.  
  Example fields:  
  - id (PK)  
  - name  
  - date  
  - location  
  - price  

- **registrations**  
  Connects participants to events.  
  Fields:  
  - id (PK)  
  - participant_id (FK)  
  - event_id (FK)  
  - registration_status (`Pending`, `Verified`, `CheckedIn`)  
  - kit_status (`Pending`, `Delivered`)  

- **payments**  
  Stores participant payments.  
  Fields:  
  - id (PK)  
  - registration_id (FK)  
  - amount  
  - status (`Submitted`, `Verified`, `Rejected`)  
  - proof_file_url  

- **qr_tokens**  
  Stores generated QR codes for each participant.  
  Fields:  
  - id (PK)  
  - participant_id (FK)  
  - token (QR string)  
  - generated_at (timestamp)  

- **checkin_logs**  
  Audit log of check-ins.  
  Fields:  
  - id (PK)  
  - participant_id (FK)  
  - event_id (FK)  
  - checkin_time  
  - staff_id (who performed the check-in)  

---

## Operational Flows

1. **Registration**  
   - Participant fills out the web form.  
   - Uploads payment proof.  
   - Data is stored in `participants` and `registrations`.  

2. **Manual Payment Verification**  
   - Operations team reviews payment proof.  
   - Sets `payments.status` to `Verified`.  
   - Trigger automatically updates `registrations.registration_status` to `Verified`.  

3. **QR Generation & Email**  
   - Trigger/function generates a unique QR when registration is verified.  
   - QR is automatically emailed to the participant.  

4. **Event Check-in**  
   - Staff scans participant QR with minimal app.  
   - System validates registration and payment.  
   - `registrations.registration_status` updated to `CheckedIn`, `kit_status` updated to `Delivered`.  
   - Audit logs record staff and timestamp in `checkin_logs`.  

---

## Roles & Row-Level Security (RLS)

- **Admin**: Full access, can create events and modify any record.  
- **Ops/Staff**: Limited access to verify payments and record check-ins.  
- **Participants**: Access only to the registration form and their QR.  

> All access controlled through **RLS policies** in Supabase.

---

## Setup Instructions (Supabase / PostgreSQL)

1. Create a Supabase project.  
2. Create tables based on the data model above.  
3. Add triggers/functions for:  
   - Updating registration status when payment is verified.  
   - Automatically generating QR codes.  
   - Logging check-ins and kit delivery.  
4. Configure RLS and roles.  
5. (Optional) Insert test data using SQL or the registration form.  

---

## Testing & Demo

- Create a test event with date, location, and price.  
- Register several participants via the web form.  
- Upload payment proofs.  
- Verify payments manually and confirm QR codes are generated and emailed.  
- Simulate QR scan at event and verify `CheckedIn` and `kit_status` updates.  
