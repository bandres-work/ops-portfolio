# La Lujaneta – Pilgrimage Registration & Operations System

![Status](https://img.shields.io/badge/Status-Production%20Ready-success)
![Version](https://img.shields.io/badge/Version-v7.0-blue)
![Security](https://img.shields.io/badge/Security-RLS%20Protected-red)
![Stack](https://img.shields.io/badge/Tech-Supabase%20%7C%20JS%20Vanilla%20%7C%20PostgreSQL-3ecf8e)

## 📌 Project Overview

**La Lujaneta Ops** is a specialized, full-stack Event Operations System designed to manage the logistics, security, and access control for large-scale pilgrimages in Argentina.

Unlike standard form builders, this system functions as a tailored **Operational CRM** that handles the entire participant lifecycle: from identity verification and payment auditing to high-speed biometric/QR access control in the field.

**Key Engineering Highlight:** The system features a **"Zero-Friction" Access Control** architecture (Scanner V7) with hybrid inputs (Camera/Manual), "Anti-Freeze" camera logic for low-end devices, and a persistent **Conflictive User Blacklist** to ensure staff safety.

---

## 🚀 Key Modules & Features

### 1. Smart Registration Portal (`index.html`)
A mobile-first frontend optimized for high-conversion data entry and data integrity.
* **Identity Resolution:** The system checks the `doc_number` against the historical `participants` database before creating a record. This prevents duplicates and links new registrations to existing medical histories.
* **Conditional Logic:** Dynamic UI that only requests specific medical/allergy details if the user toggles the corresponding flags.
* **Secure Storage:** Direct integration with **Supabase Storage** for secure, UUID-linked payment proof uploads.

### 2. Operations Dashboard (`admin.html`)
A "God Mode" protected panel for the Operations and Finance teams.
* **Real-Time KPIs:** Live monitoring of Total Registrations, Verified Revenue, and Pending Audits.
* **Visual Auditing:** A modal interface to inspect payment receipts side-by-side with user data for rapid Approve/Reject decisions.
* **Behavioral Risk Management (Blacklist):** Staff can flag participants as "Conflictive" (e.g., for past aggression). This flag is **persistent** across years/events and triggers immediate security alerts upon future interactions.
* **Data Export:** One-click generation of sanitized `.csv` reports for logistics planning (transport, t-shirt sizes).

### 3. Field Scanner V7 (`scanner.html`)
A robust PWA-like web scanner designed for high-stress, low-connectivity environments.
* **Hybrid Input System:**
    * **Camera:** High-speed UUID QR scanning using `html5-qrcode`.
    * **Manual Fallback:** Dedicated DNI search for users with broken screens or dead batteries.
* **Intelligent Validation Logic:**
    1.  **Identity Check:** Does the user exist?
    2.  **Registration Check:** Is the user registered for *this specific event*?
    3.  **Status Check:** Has the kit already been delivered? (Prevents double-dipping).
    4.  **Security Check:** **Is the user flagged as Conflictive?** (Triggers a severe Black/Red alert).
    5.  **Health Check:** Does the user have critical medical conditions? (Triggers a Red alert).
* **"Anti-Freeze" Logic:** A custom algorithm that automatically manages the camera lifecycle (Stop/Start) to prevent browser freezes on mobile devices after scanning.

---

## 🛠️ Technical Architecture

The system is built on a **Serverless / BaaS (Backend as a Service)** architecture to maximize scalability and minimize maintenance costs.

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Frontend** | Vanilla JS (ES6+) | No frameworks, no build steps. Optimized for raw performance (<1s load time). |
| **Backend** | Supabase | Provides Authentication, Database, and Storage APIs. |
| **Database** | PostgreSQL 15 | Relational model with strong data integrity (Foreign Keys, Constraints). |
| **Security** | RLS (Row Level Security) | Database policies ensure public users can only `INSERT`, while only authenticated Staff can `SELECT`/`UPDATE`. |
| **Scanning** | Html5-Qrcode | Browser-based barcode recognition library. |

### Database Schema (Simplified)

The data model separates the *Person* from the *Event Registration* to allow multi-year history tracking.

* **`participants`**: (The User) `id`, `doc_number`, `full_name`, `medical_notes`, `is_flagged` (Blacklist), `flag_notes`.
* **`registrations`**: (The Link) `id`, `participant_id`, `event_id`, `payment_status` (ENUM), `kit_status` (ENUM), `checked_in`.
* **`payments`**: (The Transaction) `id`, `registration_id`, `proof_url`, `amount`, `status`.

---

## 🛡️ Security & Access Control

* **Session Guard:** Critical operational files (`admin.html`, `scanner.html`) implement a strict session check on load. If `supabase.auth.getSession()` returns null, the user is forcibly redirected to the Login page.
* **Role-Based Logic:** The dashboard UI adapts based on the user's role. "Approve/Reject" buttons are removed for read-only staff.
* **Input Sanitization:** All database interactions use parameterized Supabase client methods to prevent SQL Injection.

---

## 📥 Setup & Installation

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/bandres-work/ops-portfolio.git](https://github.com/bandres-work/ops-portfolio.git)
    ```

2.  **Supabase Configuration:**
    * Create a new project on [Supabase](https://supabase.com).
    * Run the `database_setup.sql` script (included in repo) in the SQL Editor to create tables and RLS policies.
    * Create a public storage bucket named `payments`.

3.  **Environment Variables:**
    * Open `script.js`, `admin.js`, and `scanner.html`.
    * Replace `const SUPABASE_URL` and `const SUPABASE_KEY` with your project's API credentials.

4.  **Deploy:**
    * The project is static. You can drag and drop the folder into **Netlify** or serve it via **GitHub Pages**.

---

## 🔮 Future Roadmap

* **Automated Emails:** Implement Supabase Edge Functions to send the QR code via email immediately upon payment verification.
* **Offline Mode:** Implement Service Workers (PWA) to allow the scanner to cache database subsets and function without internet connectivity.
* **Metrics Dashboard:** Advanced data visualization for "Peak Arrival Times" and revenue forecasting.

---

<p align="center">
  Built by <strong>bandres-work</strong>
</p>

