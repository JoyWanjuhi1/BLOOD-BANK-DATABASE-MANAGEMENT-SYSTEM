# BLOOD-BANK-DATABASE-MANAGEMENT-SYSTEM
An enterprise-level relational database system designed in SSMS to track blood donor eligibility, manage critical patient urgencies, and handle real-time perishable inventory through automated triggers and multi-table analytics.

# Enterprise Blood Bank Information & Cross-Match Analytics System

## 📌 Project Overview

This project implements a production-grade relational database blueprint for a medical healthcare framework tracking critical blood donor registers, active patient clinical urgencies, and live perishable inventory assets.

The goal of this portfolio piece is to demonstrate advanced backend database engineering using Microsoft SQL Server (T-SQL) via SQL Server Management Studio (SSMS). It showcases complex multi-table tracking, relational check constraints, automated inventory triggers, and high-stakes medical business intelligence computations.

---

## 🛠️ 1. Database Architecture & Schema

The database uses a highly structured relational layout engineered across **6 integrated tables** to maintain strict referential data integrity. It employs Primary Keys, Foreign Keys, `UNIQUE` constraints, and conditional `CHECK` filters to manage perishable biological materials safely.

* **BloodTypes Table:** Core reference classification mapping universal groups (e.g., O+, AB-).
* **Donors Table:** Tracks identity records alongside chronological tracking of physical historical donation dates.
* **Patients Table:** Tracks active healthcare facility placements and hospital emergency priority tiers.
* **BloodInventory Table:** Tracks unique storage bags, individual volumes ($ml$), and real-time shelf-life viability windows.
* **TransfusionRecords Table:** The operational ledger mapping out successful distributions from specific inventory units straight to recipients.

### Database Entity-Relationship Map

The complete structural creation script can be found in **`01_schema.sql`** in this repository.

---

## ⚙️ 2. Real-Time Inventory Automation (Database Triggers)

To eliminate manual data entry errors and guarantee absolute alignment between physical medical stock and the data registry, a custom `AFTER INSERT` database trigger (`trg_UpdateBloodStatus`) was implemented on the distribution ledger.

Whenever an active transfusion event is logged in `TransfusionRecords`, the system automatically runs a matching logical calculation to isolate the respective blood bag and alter its operational state in real time:

$$\text{Blood Bag Inventory Status} = \text{'TRANSFUSED'}$$

This automated constraint locks down the unit, preventing expired or previously spent biological materials from being reallocated to other patient fields.

---

## 📊 3. Advanced Business Computations & Analytics

The core engine of this platform is its ability to perform high-velocity calculations that cross-reference operational supply chains with real-time patient demands.

### A. Safety Stock Buffer & Deficit Matrix

**Business Use:** Evaluates active unexpired storage volumes against high-urgency hospital cases to flag operational supply gaps across the medical network using a standard 3-bag safety threshold ($1350\text{ ml}$).

* **SQL Elements Used:** `LEFT JOIN`, `ISNULL()`, Multi-table grouping, conditional mathematical division.

```sql
SELECT 
    bt.blood_group,
    COUNT(DISTINCT bi.bag_id) AS available_bags_count,
    ISNULL(SUM(bi.volume_ml), 0) AS total_available_volume_ml,
    COUNT(DISTINCT p.patient_id) AS critical_patients_count,
    CASE 
        WHEN ISNULL(SUM(bi.volume_ml), 0) >= 1350 THEN 'SAFE BUFFER'
        WHEN ISNULL(SUM(bi.volume_ml), 0) BETWEEN 1 AND 1349 THEN 'LOW STOCK WARNING'
        ELSE 'CRITICAL DEFICIT'
    END AS safety_status,
    CAST((ISNULL(SUM(bi.volume_ml), 0) / 1350.0) * 100 AS DECIMAL(5,2)) AS safety_target_percentage
FROM BloodTypes bt
LEFT JOIN BloodInventory bi ON bt.blood_type_id = bi.blood_type_id 
    AND bi.status = 'AVAILABLE' 
    AND bi.expiry_date > GETDATE()
LEFT JOIN Patients p ON bt.blood_type_id = p.blood_type_id AND p.medical_urgency = 'CRITICAL'
GROUP BY bt.blood_group;

```

### B. Automated Donor Recruitment & Eligibility Logs

**Business Use:** Computes active donor availability windows using distinct medical cooldown tracking parameters based on gender boundaries ($84\text{ days for males}\ /\ 112\text{ days for females}$) to feed communications frameworks.

* **SQL Elements Used:** `INNER JOIN`, `DATEDIFF()`, Nested conditional `CASE WHEN` branches.

```sql
SELECT 
    d.donor_id,
    d.first_name + ' ' + d.last_name AS donor_full_name,
    bt.blood_group,
    d.gender,
    DATEDIFF(day, d.last_donation_date, GETDATE()) AS days_since_last_donation,
    CASE 
        WHEN d.last_donation_date IS NULL THEN 'ELIGIBLE'
        WHEN d.gender = 'Male' AND DATEDIFF(day, d.last_donation_date, GETDATE()) >= 84 THEN 'ELIGIBLE'
        WHEN d.gender = 'Female' AND DATEDIFF(day, d.last_donation_date, GETDATE()) >= 112 THEN 'ELIGIBLE'
        ELSE 'INELIGIBLE (COOLDOWN)'
    END AS current_eligibility_status,
    CASE 
        WHEN d.gender = 'Male' AND DATEDIFF(day, d.last_donation_date, GETDATE()) < 84 THEN 84 - DATEDIFF(day, d.last_donation_date, GETDATE())
        WHEN d.gender = 'Female' AND DATEDIFF(day, d.last_donation_date, GETDATE()) < 112 THEN 112 - DATEDIFF(day, d.last_donation_date, GETDATE())
        ELSE 0
    END AS days_until_next_eligible
FROM Donors d
INNER JOIN BloodTypes bt ON d.blood_type_id = bt.blood_type_id;

```

### C. Full-Chain Biocompatibility Audit Logs

**Business Use:** Generates standard clinical audit histories tracing biological assets backward from recipient patient endpoints directly to initial collection sessions.

* **SQL Elements Used:** 5-Table `INNER JOIN` structure, String Concatenation, chronological sorting.

```sql
SELECT 
    tr.transfusion_id,
    tr.transfusion_date,
    bt.blood_group AS patient_blood_group,
    tr.volume_transfused_ml,
    p.first_name + ' ' + p.last_name AS recipient_name,
    p.hospital_name,
    bi.bag_id AS blood_bag_serial_number,
    bi.collection_date
FROM TransfusionRecords tr
INNER JOIN Patients p ON tr.patient_id = p.patient_id
INNER JOIN BloodInventory bi ON tr.bag_id = bi.bag_id
INNER JOIN BloodTypes bt ON p.blood_type_id = bt.blood_type_id;

```

### D. Inventory Expiration & Waste Analysis

**Business Use:** Isolate specific operational asset failures by partitioning wasted biological products and indexing them by length of time past viability parameters.

* **SQL Elements Used:** Common Table Expressions (CTEs), Partitioned Window Functions (`DENSE_RANK() OVER`).

```sql
WITH ExpiredRanks AS (
    SELECT 
        bt.blood_group,
        bi.bag_id,
        bi.expiry_date,
        DATEDIFF(day, bi.expiry_date, GETDATE()) AS days_past_expiry,
        DENSE_RANK() OVER (PARTITION BY bt.blood_type_id ORDER BY bi.expiry_date ASC) AS waste_priority_rank
    FROM BloodInventory bi
    JOIN BloodTypes bt ON bi.blood_type_id = bt.blood_type_id
    WHERE bi.status = 'EXPIRED' OR bi.expiry_date < GETDATE()
)
SELECT blood_group, bag_id, expiry_date, days_past_expiry, waste_priority_rank
FROM ExpiredRanks
WHERE waste_priority_rank <= 3;

```

---

## 🚀 4. Technical Skills Proven

* **Relational Database Design:** Normalization patterns, Primary/Foreign keys, strict conditional domain constraints.
* **Advanced Query Optimization:** 5-Table join structures, conditional column logic matrices, programmatic data filters.
* **Enterprise Features:** Structural Common Table Expressions (CTEs), Window calculations, automated database Triggers.
* **Data-Driven Healthcare BI:** Medical tracking simulation, chronological trend tracing, data modeling.
