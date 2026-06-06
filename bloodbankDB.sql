-- 1. Initialize the Database
CREATE DATABASE BloodBankDB;
GO
USE BloodBankDB;
GO

-- 2. Create Blood Types Reference Table
CREATE TABLE BloodTypes (
    blood_type_id INT PRIMARY KEY IDENTITY(1,1),
    blood_group VARCHAR(5) NOT NULL UNIQUE -- E.g., 'A+', 'O-', 'AB+'
);

-- 3. Create Donors Table
CREATE TABLE Donors (
    donor_id INT PRIMARY KEY IDENTITY(1,1),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    blood_type_id INT FOREIGN KEY REFERENCES BloodTypes(blood_type_id),
    gender VARCHAR(10) CHECK (gender IN ('Male', 'Female', 'Other')),
    date_of_birth DATE NOT NULL,
    contact_phone VARCHAR(20),
    email VARCHAR(100),
    last_donation_date DATE
);

-- 4. Create Patients Table
CREATE TABLE Patients (
    patient_id INT PRIMARY KEY IDENTITY(1,1),
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    blood_type_id INT FOREIGN KEY REFERENCES BloodTypes(blood_type_id),
    hospital_name VARCHAR(150) NOT NULL,
    medical_urgency VARCHAR(15) CHECK (medical_urgency IN ('CRITICAL', 'HIGH', 'NORMAL'))
);

-- 5. Create Blood Inventory Inventory Table
CREATE TABLE BloodInventory (
    bag_id INT PRIMARY KEY IDENTITY(1,1),
    blood_type_id INT FOREIGN KEY REFERENCES BloodTypes(blood_type_id),
    volume_ml INT NOT NULL DEFAULT 450 CHECK (volume_ml > 0),
    collection_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    status VARCHAR(15) DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE', 'TRANSFUSED', 'EXPIRED'))
);

-- 6. Create Transfusion Records Table
    CREATE TABLE TransfusionRecords (
    transfusion_id INT PRIMARY KEY IDENTITY(1,1),
    bag_id INT FOREIGN KEY REFERENCES BloodInventory(bag_id),
    patient_id INT FOREIGN KEY REFERENCES Patients(patient_id),
    transfusion_date DATE NOT NULL,
    volume_transfused_ml INT NOT NULL CHECK (volume_transfused_ml > 0)
);

SELECT 
    bt.blood_group,
    COUNT(DISTINCT bi.bag_id) AS available_bags_count,
    ISNULL(SUM(bi.volume_ml), 0) AS total_available_volume_ml,
    COUNT(DISTINCT p.patient_id) AS critical_patients_count,
    -- Medical threshold math: Target safety buffer is 3 bags (1350ml) per group
    CASE 
        WHEN ISNULL(SUM(bi.volume_ml), 0) >= 1350 THEN 'SAFE BUFFER'
        WHEN ISNULL(SUM(bi.volume_ml), 0) BETWEEN 1 AND 1349 THEN 'LOW STOCK WARNING'
        ELSE 'CRITICAL DEFICIT'
    END AS safety_status,
    -- Percentage computation against the 1350ml safety threshold
    CAST((ISNULL(SUM(bi.volume_ml), 0) / 1350.0) * 100 AS DECIMAL(5,2)) AS safety_target_percentage
FROM BloodTypes bt
LEFT JOIN BloodInventory bi ON bt.blood_type_id = bi.blood_type_id 
    AND bi.status = 'AVAILABLE' 
    AND bi.expiry_date > GETDATE()
LEFT JOIN Patients p ON bt.blood_type_id = p.blood_type_id AND p.medical_urgency = 'CRITICAL'
GROUP BY bt.blood_group
ORDER BY total_available_volume_ml DESC;

SELECT 
    d.donor_id,
    d.first_name + ' ' + d.last_name AS donor_full_name,
    bt.blood_group,
    d.gender,
    d.last_donation_date,
    DATEDIFF(day, d.last_donation_date, GETDATE()) AS days_since_last_donation,
    -- Conditional check constraint simulation via text states
    CASE 
        WHEN d.last_donation_date IS NULL THEN 'ELIGIBLE'
        WHEN d.gender = 'Male' AND DATEDIFF(day, d.last_donation_date, GETDATE()) >= 84 THEN 'ELIGIBLE'
        WHEN d.gender = 'Female' AND DATEDIFF(day, d.last_donation_date, GETDATE()) >= 112 THEN 'ELIGIBLE'
        ELSE 'INELIGIBLE (COOLDOWN)'
    END AS current_eligibility_status,
    -- Computes precise remaining countdown timelines
    CASE 
        WHEN d.gender = 'Male' AND DATEDIFF(day, d.last_donation_date, GETDATE()) < 84 THEN 84 - DATEDIFF(day, d.last_donation_date, GETDATE())
        WHEN d.gender = 'Female' AND DATEDIFF(day, d.last_donation_date, GETDATE()) < 112 THEN 112 - DATEDIFF(day, d.last_donation_date, GETDATE())
        ELSE 0
    END AS days_until_next_eligible
FROM Donors d
INNER JOIN BloodTypes bt ON d.blood_type_id = bt.blood_type_id
ORDER BY current_eligibility_status ASC, days_until_next_eligible DESC;

SELECT 
    tr.transfusion_id,
    tr.transfusion_date,
    bt.blood_group AS patient_blood_group,
    tr.volume_transfused_ml,
    -- Patient Context
    p.first_name + ' ' + p.last_name AS recipient_name,
    p.hospital_name,
    p.medical_urgency,
    -- Physical Inventory Trace
    bi.bag_id AS blood_bag_serial_number,
    bi.collection_date,
    bi.status AS current_bag_status
FROM TransfusionRecords tr
INNER JOIN Patients p ON tr.patient_id = p.patient_id
INNER JOIN BloodInventory bi ON tr.bag_id = bi.bag_id
INNER JOIN BloodTypes bt ON p.blood_type_id = bt.blood_type_id
ORDER BY tr.transfusion_date DESC;

WITH ExpiredRanks AS (
    SELECT 
        bt.blood_group,
        bi.bag_id,
        bi.collection_date,
        bi.expiry_date,
        DATEDIFF(day, bi.expiry_date, GETDATE()) AS days_past_expiry,
        DENSE_RANK() OVER (PARTITION BY bt.blood_type_id ORDER BY bi.expiry_date ASC) AS waste_priority_rank
    FROM BloodInventory bi
    JOIN BloodTypes bt ON bi.blood_type_id = bt.blood_type_id
    WHERE bi.status = 'EXPIRED' OR bi.expiry_date < GETDATE()
)
SELECT 
    blood_group,
    bag_id,
    collection_date,
    expiry_date,
    days_past_expiry,
    waste_priority_rank
FROM ExpiredRanks
WHERE waste_priority_rank <= 3; -- Displays only the top 3 critical asset failures per partition group
