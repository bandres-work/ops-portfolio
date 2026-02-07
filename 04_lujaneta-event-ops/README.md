# La Lujaneta – Pilgrimage Registration & Operations System

**Phase 1: Digital Registration, Payment Auditing & Access Control**

## 📌 Project Overview
This project is a specialized Event Operations System designed to manage the annual pilgrimage "La Lujaneta" (Argentina). It automates the intake of thousands of participants, manages complex payment verification flows, and generates secure digital credentials (QR) for kit delivery and attendance tracking.

Unlike standard form builders, this system handles **identity deduplication** (returning pilgrims are recognized automatically), **conditional medical logic**, and **secure payment proof uploads** directly to Supabase Storage.

## 🚀 Key Features (Phase 1 - Implemented)

### 1. Smart Registration Frontend
* **Identity Resolution:** The system checks if a participant exists by Document Number (DNI) before creating a new record. If they exist, it links the new registration to the existing identity, maintaining a clean history.
* **Conditional Logic:** "Yes/No" toggles for Medical Conditions and Allergies. Detail fields only appear when necessary, keeping the UI clean.
* **UX/UI:** Fully responsive design (Mobile First) using modern CSS variables.
* **Payment Integration:** Displays local payment methods (CBU/Alias) and handles file uploads for transfer receipts.

### 2. Robust Backend (Supabase / PostgreSQL)
* **Row Level Security (RLS):** configured to allow public submissions (INSERT) while protecting sensitive data from unauthorized reading.
* **Automated Auditing:** Custom PL/PGSQL triggers (`audit_changes`) log every insert, update, or delete action in the `audit_log` table.
* **State Management:** Strict usage of PostgreSQL ENUMs for statuses:
    * `payment_status`: Submitted → Verified / Rejected
    * `kit_status`: NotEligible → Eligible → Delivered
* **Storage Security:** Policies configured to allow public uploads of payment proofs only to the specific `payments` bucket.

## 🛠️ Tech Stack

* **Frontend:** HTML5, CSS3 (Custom Variables), JavaScript (ES6+ Modules).
* **Backend:** Supabase (PostgreSQL 15+).
* **Storage:** Supabase Storage (Image/PDF handling).
* **Infrastructure:** Row Level Security (RLS), Database Triggers, PL/PGSQL Functions.

## 🗄️ Database Model

The system uses a relational model optimized for recurring events:

### Core Tables
| Table | Description | Key Fields |
| :--- | :--- | :--- |
| **`participants`** | Stores unique human identity. | `id`, `doc_number`, `medical_flag`, `full_name` |
| **`events`** | Configuration for specific pilgrimage years. | `id`, `event_code`, `price`, `active` |
| **`registrations`** | Links a participant to an event. | `id`, `status`, `kit_status`, `fitness_level` |
| **`payments`** | Tracks financial transactions & proofs. | `id`, `amount`, `proof_url`, `status` (ENUM) |
| **`checkins`** | Operational logs for the event day. | `id`, `scanned_by`, `scanned_at`, `result` |

### Security & Automation
* **`qr_tokens`**: Stores the secure string used for QR generation.
* **`audit_log`**: JSONB storage for tracking all data changes.
* **Triggers**:
    * `trg_sync_kit_status`: Automatically updates kit eligibility when payment is verified.
    * `trg_scan_qr`: Handles the logic when a QR is scanned (checks payment, logs attendance).

## ⚙️ Operational Flows

1.  **Registration:** User fills the web form. JS checks for duplicates.
2.  **Upload:** Payment proof is uploaded to Supabase Storage.
3.  **Submission:** Data is inserted into `participants` (if new), `registrations`, and `payments`.
4.  **Verification (Next Step):** Ops team reviews proof via Admin Panel.
5.  **QR Dispatch (Next Step):** System emails the QR code upon verification.

## 📥 Setup & Installation

1.  **Clone the Repository**
    ```bash
    git clone [https://github.com/your-username/ops-portfolio.git](https://github.com/your-username/ops-portfolio.git)
    cd ops-portfolio/04_lujaneta-event-ops
    ```

2.  **Database Setup**
    * Create a new project in [Supabase](https://supabase.com).
    * Copy the content of `database_setup.sql`.
    * Run it in the Supabase **SQL Editor** to create tables, enums, and triggers.

3.  **Storage Setup**
    * Create a public bucket named `payments`.
    * Run the storage policy SQL to allow public uploads.

4.  **Frontend Configuration**
    * Open `script.js`.
    * Update `SUPABASE_URL` and `SUPABASE_KEY` (Anon) with your project credentials.
    * Update `EVENT_ID` with the UUID of the active event.

5.  **Run**
    * Open `index.html` in your browser (or use Live Server).

## 🔮 Roadmap (Phase 2)

* **Admin Dashboard:** Private panel for Operations Staff to approve/reject payments visually.
* **Email Automation:** Edge Function to send the QR code via email upon `payment_status = 'Verified'`.
* **Scanner App:** Mobile-friendly interface for the Check-in Staff to scan QRs at the event.

