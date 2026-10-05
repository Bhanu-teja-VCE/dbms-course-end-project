-- ============================================================================
-- BANK LOAN MANAGEMENT SYSTEM: EMI PROCESSING, REPAYMENT TRACKING & RISK ASSESSMENT
-- Stage 5: Database Normalization Theory, Formal Proofs & Practical Decomposition
-- Database: MySQL 8.0+ (InnoDB)
-- Database Name: bank_loan_db
-- ============================================================================

USE bank_loan_db;

-- ============================================================================
-- SECTION 1: THE UNNORMALIZED RELATION (LOAN_RAW)
-- ============================================================================
-- An unnormalized relation (often called a "flat spreadsheet" or "universal relation")
-- compresses multiple real-world entities (Applicant, Product, Guarantor, Loan,
-- EMI Schedule, Repayment) into a single wide table.
--
-- SCHEMA DEFINITION:
-- LOAN_RAW(loan_id, applicant_name, applicant_email, applicant_pan, product_name,
--          product_type, interest_rate, guarantor_name, guarantor_phone,
--          principal, tenure, emi_amount, installment_no, due_date,
--          principal_comp, interest_comp, amount_paid, payment_date)
-- ============================================================================

DROP TABLE IF EXISTS LOAN_RAW;

CREATE TABLE LOAN_RAW (
    loan_id          INT,
    applicant_name   VARCHAR(100),
    applicant_email  VARCHAR(100),
    applicant_pan    VARCHAR(10),
    product_name     VARCHAR(100),
    product_type     VARCHAR(30),
    interest_rate    DECIMAL(5,2),
    guarantor_name   VARCHAR(100),
    guarantor_phone  VARCHAR(15),
    principal        DECIMAL(12,2),
    tenure           INT,
    emi_amount       DECIMAL(12,2),
    installment_no   INT,
    due_date         DATE,
    principal_comp   DECIMAL(12,2),
    interest_comp    DECIMAL(12,2),
    amount_paid      DECIMAL(12,2),
    payment_date     DATE
) ENGINE=InnoDB;

-- Inserting realistic sample data showing multiple loans, multiple installments,
-- and duplicate information across tuples:
INSERT INTO LOAN_RAW VALUES
(1001, 'Rajesh Kumar Verma', 'rajesh.verma@gmail.com', 'ABCDE1234F', 'SBI Regular Home Loan', 'HOME', 8.50, 'Suresh Chandra Verma', '+919876543210', 2500000.00, 120, 31010.00, 1, '2024-01-05', 13301.67, 17708.33, 31010.00, '2024-01-04'),
(1001, 'Rajesh Kumar Verma', 'rajesh.verma@gmail.com', 'ABCDE1234F', 'SBI Regular Home Loan', 'HOME', 8.50, 'Suresh Chandra Verma', '+919876543210', 2500000.00, 120, 31010.00, 2, '2024-02-05', 13395.94, 17614.06, 31010.00, '2024-02-05'),
(1001, 'Rajesh Kumar Verma', 'rajesh.verma@gmail.com', 'ABCDE1234F', 'SBI Regular Home Loan', 'HOME', 8.50, 'Suresh Chandra Verma', '+919876543210', 2500000.00, 120, 31010.00, 3, '2024-03-05', 13490.81, 17519.19, NULL,     NULL),
(1002, 'Priya Lakshmi Sundaram', 'priya.s@yahoo.co.in', 'BCDEF2345G', 'SBI Xpress Credit Personal Loan', 'PERSONAL', 11.25, NULL, NULL, 500000.00, 36, 16428.00, 1, '2024-02-10', 11740.50, 4687.50, 16428.00, '2024-02-09'),
(1002, 'Priya Lakshmi Sundaram', 'priya.s@yahoo.co.in', 'BCDEF2345G', 'SBI Xpress Credit Personal Loan', 'PERSONAL', 11.25, NULL, NULL, 500000.00, 36, 16428.00, 2, '2024-03-10', 11850.57, 4577.43, NULL,     NULL),
(1003, 'Amitabh Vikram Sen', 'amitabh.sen@rediffmail.com', 'CDEFG3456H', 'SBI Car Loan Prime', 'VEHICLE', 8.75, 'Vikramaditya Sen', '+919811122233', 1000000.00, 60, 20637.00, 1, '2024-01-15', 13345.33, 7291.67, 20637.00, '2024-01-14'),
(1003, 'Amitabh Vikram Sen', 'amitabh.sen@rediffmail.com', 'CDEFG3456H', 'SBI Car Loan Prime', 'VEHICLE', 8.75, 'Vikramaditya Sen', '+919811122233', 1000000.00, 60, 20637.00, 2, '2024-02-15', 13442.61, 7194.39, 20637.00, '2024-02-15'),
(1003, 'Amitabh Vikram Sen', 'amitabh.sen@rediffmail.com', 'CDEFG3456H', 'SBI Car Loan Prime', 'VEHICLE', 8.75, 'Vikramaditya Sen', '+919811122233', 1000000.00, 60, 20637.00, 3, '2024-03-15', 13540.63, 7096.37, NULL,     NULL);


-- ============================================================================
-- SECTION 2: FORMAL SPECIFICATION OF FUNCTIONAL DEPENDENCIES (FDs)
-- ============================================================================
/*
A Functional Dependency (X -> Y) represents a semantic constraint between two sets 
of attributes X and Y in relation R, such that for any two tuples t1 and t2 in R:
    If t1[X] = t2[X], then t1[Y] MUST equal t2[Y].

In LOAN_RAW, the business rules and financial domain enforce the following set F of FDs:

--------------------------------------------------------------------------------
FD1: loan_id -> applicant_name, applicant_email, applicant_pan, product_name,
               product_type, interest_rate, guarantor_name, guarantor_phone,
               principal, tenure, emi_amount
Semantic Meaning:
    Each loan sanction is uniquely identified by `loan_id`. A single loan agreement
    has exactly one primary applicant, belongs to one product type, has one agreed
    interest rate, one optional guarantor, a fixed principal, tenure, and calculated EMI.

--------------------------------------------------------------------------------
FD2: applicant_email -> applicant_name, applicant_pan
Semantic Meaning:
    In modern digital banking KYC, an applicant's verified email address uniquely
    identifies the individual customer and determines their legal name and PAN.

--------------------------------------------------------------------------------
FD3: {loan_id, installment_no} -> due_date, principal_comp, interest_comp,
                                 amount_paid, payment_date
Semantic Meaning:
    An installment schedule is uniquely identified by the combination of the loan
    and the specific installment sequence number (e.g., Month 1, Month 2).
    This composite key uniquely determines the amortization breakdown and payment history.

--------------------------------------------------------------------------------
FD4: product_name -> product_type, interest_rate
Semantic Meaning:
    The standard bank catalog product (e.g. 'SBI Regular Home Loan') defines
    its category (HOME) and the base rack interest rate (8.50%).

--------------------------------------------------------------------------------
FD5: applicant_pan -> applicant_name, applicant_email
Semantic Meaning:
    The Permanent Account Number (PAN) is a statutory 10-character alphanumeric
    identifier issued by the Income Tax Department of India. It is globally unique
    per tax-paying citizen, uniquely identifying the customer and their email.
--------------------------------------------------------------------------------
*/


-- ============================================================================
-- SECTION 3: ATTRIBUTE CLOSURE ALGORITHM & CANDIDATE KEY DETERMINATION
-- ============================================================================
/*
ALGORITHM: Attribute Closure Computation (X+) under set of FDs F
Input:  Set of attributes X, Set of Functional Dependencies F
Output: Attribute closure X+

Step 0: Initialize X+ = X
Step 1: Repeat until no more attributes can be added to X+:
        For each FD (Y -> Z) in F:
            If Y ⊆ X+, then X+ = X+ ∪ Z
Step 2: Return X+

--------------------------------------------------------------------------------
TRACE: Computing the Attribute Closure of X = {loan_id, installment_no}
--------------------------------------------------------------------------------
Iteration 0:
    X+(0) = {loan_id, installment_no}

Iteration 1:
    - Examine FD1: loan_id -> {applicant_name, applicant_email, applicant_pan,
                              product_name, product_type, interest_rate,
                              guarantor_name, guarantor_phone, principal, tenure,
                              emi_amount}
      Since {loan_id} ⊆ X+(0):
      X+(1) = {loan_id, installment_no, applicant_name, applicant_email, applicant_pan,
               product_name, product_type, interest_rate, guarantor_name,
               guarantor_phone, principal, tenure, emi_amount}

Iteration 2:
    - Examine FD3: {loan_id, installment_no} -> {due_date, principal_comp, interest_comp,
                                                amount_paid, payment_date}
      Since {loan_id, installment_no} ⊆ X+(1):
      X+(2) = {loan_id, installment_no, applicant_name, applicant_email, applicant_pan,
               product_name, product_type, interest_rate, guarantor_name,
               guarantor_phone, principal, tenure, emi_amount,
               due_date, principal_comp, interest_comp, amount_paid, payment_date}

Iteration 3:
    - Examine FD4: product_name -> {product_type, interest_rate}
      {product_name} ⊆ X+(2), attributes already in closure.
    - Examine FD2: applicant_email -> {applicant_name, applicant_pan}
      {applicant_email} ⊆ X+(2), attributes already in closure.
    - Examine FD5: applicant_pan -> {applicant_name, applicant_email}
      {applicant_pan} ⊆ X+(2), attributes already in closure.

No further attributes can be added. Fixed point reached!

Result:
    {loan_id, installment_no}+ = ALL 18 ATTRIBUTES of LOAN_RAW.

CONCLUSION:
1. Superkey: Since {loan_id, installment_no}+ derives all attributes in LOAN_RAW,
   {loan_id, installment_no} is a SUPERKEY.
2. Minimality Check:
   - Does {loan_id}+ contain all attributes?
     {loan_id}+ = {loan_id, applicant_name, applicant_email, applicant_pan,
                   product_name, product_type, interest_rate, guarantor_name,
                   guarantor_phone, principal, tenure, emi_amount}
     It DOES NOT contain installment_no, due_date, principal_comp, interest_comp, etc.
   - Does {installment_no}+ contain all attributes?
     {installment_no}+ = {installment_no}
     It derives no other attributes.
   Therefore, no proper subset of {loan_id, installment_no} is a superkey.

3. Candidate Key:
   {loan_id, installment_no} is the MINIMAL CANDIDATE KEY (and Primary Key) of LOAN_RAW.

PRIME vs NON-PRIME ATTRIBUTES:
- Prime Attributes (part of a candidate key):
  {loan_id, installment_no}
- Non-Prime Attributes (not part of any candidate key):
  {applicant_name, applicant_email, applicant_pan, product_name, product_type,
   interest_rate, guarantor_name, guarantor_phone, principal, tenure, emi_amount,
   due_date, principal_comp, interest_comp, amount_paid, payment_date}
*/


-- ============================================================================
-- SECTION 4: DEMONSTRATION OF DATA ANOMALIES IN UNNORMALIZED FORM
-- ============================================================================
/*
Because LOAN_RAW combines facts about Applicants, Products, Guarantors, Loans,
Schedules, and Payments, it suffers from all three classic Codd relational anomalies:

1. INSERTION ANOMALY:
   - Scenario A: The bank introduces a new loan product "SBI Green Solar Loan" at 7.50%.
     It cannot be inserted into LOAN_RAW without a valid loan_id, applicant, and installment!
     Because {loan_id, installment_no} is the primary key, inserting NULL for them violates
     Entity Integrity.
   - Scenario B: A new customer walks into the branch and registers their KYC details.
     We cannot store their applicant_name, email, and PAN until they take out a loan and
     generate their first installment schedule.

   SQL Example demonstrating failure / inability:
   -- INSERT INTO LOAN_RAW (product_name, product_type, interest_rate) 
   -- VALUES ('SBI Green Solar Loan', 'HOME', 7.50);
   -- FAILS: Primary key columns (loan_id, installment_no) cannot be NULL!

2. UPDATE / MODIFICATION ANOMALY:
   - Scenario: Rajesh Kumar Verma (loan_id 1001) has a 10-year loan (120 installments).
     His email, PAN, and name are duplicated across all 120 rows!
     If Rajesh updates his email from 'rajesh.verma@gmail.com' to 'rajesh.v@tcs.com',
     the system must update 120 separate records. If the server crashes after updating
     row 65, the database enters an inconsistent state where the applicant has two
     different email addresses depending on which installment is queried.

   SQL Example demonstrating the overhead:
   -- UPDATE LOAN_RAW 
   -- SET applicant_email = 'rajesh.v@tcs.com' 
   -- WHERE applicant_pan = 'ABCDE1234F';
   -- Requires modifying dozens/hundreds of rows instead of exactly 1 row!

3. DELETION ANOMALY:
   - Scenario: Amitabh Vikram Sen (loan_id 1003) finishes paying off his vehicle loan.
     If the compliance retention policy dictates purging completed loan installments,
     deleting the rows for loan_id 1003 will inadvertently erase:
     a) The entire record of Amitabh Vikram Sen as an applicant.
     b) The guarantor record of Vikramaditya Sen.
     c) If 'SBI Car Loan Prime' was only held by him, the bank permanently loses
        the catalog existence of that loan product!

   SQL Example demonstrating unintended collateral loss:
   -- DELETE FROM LOAN_RAW WHERE loan_id = 1003;
   -- Erases applicant Amitabh, guarantor Vikramaditya, and installment history simultaneously!
*/


-- ============================================================================
-- SECTION 5: STEP-BY-STEP NORMALIZATION: 1NF → 2NF → 3NF → BCNF
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: FIRST NORMAL FORM (1NF)
-- Definition: A relation R is in 1NF if and only if all underlying domains contain
-- only atomic (indivisible) values, and there are no repeating groups or arrays.
--
-- Analysis:
-- In LOAN_RAW, every column stores single, scalar values (no comma-separated lists
-- or nested tables). Thus, LOAN_RAW is structurally in 1NF.
--
-- However, LOAN_RAW is in 1NF but NOT in 2NF because of Partial Dependencies!
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- STEP 2: SECOND NORMAL FORM (2NF)
-- Definition: A relation R is in 2NF if and only if:
--   1. It is in 1NF.
--   2. Every non-prime attribute is FULLY FUNCTIONALLY DEPENDENT on every candidate key.
--      In other words, NO non-prime attribute depends on a proper subset of any candidate key
--      (No Partial Dependencies: X -> A where X ⊂ CandidateKey).
--
-- Violation in LOAN_RAW:
-- Candidate Key: {loan_id, installment_no}
-- Partial Dependency:
--   FD1: loan_id -> {applicant_name, applicant_email, applicant_pan, product_name,
--                    product_type, interest_rate, guarantor_name, guarantor_phone,
--                    principal, tenure, emi_amount}
-- Here, loan_id is a proper subset of {loan_id, installment_no}!
-- 11 non-prime attributes depend ONLY on loan_id, not on installment_no!
--
-- 2NF Decomposition:
-- Split LOAN_RAW into two relations:
-- 1. LOAN_INFO_2NF (loan_id [PK], applicant_name, applicant_email, applicant_pan,
--                   product_name, product_type, interest_rate, guarantor_name,
--                   guarantor_phone, principal, tenure, emi_amount)
-- 2. INSTALLMENT_SCHEDULE_2NF (loan_id, installment_no [Composite PK], due_date,
--                              principal_comp, interest_comp, amount_paid, payment_date)
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS INSTALLMENT_SCHEDULE_2NF;
DROP TABLE IF EXISTS LOAN_INFO_2NF;

CREATE TABLE LOAN_INFO_2NF (
    loan_id          INT PRIMARY KEY,
    applicant_name   VARCHAR(100),
    applicant_email  VARCHAR(100),
    applicant_pan    VARCHAR(10),
    product_name     VARCHAR(100),
    product_type     VARCHAR(30),
    interest_rate    DECIMAL(5,2),
    guarantor_name   VARCHAR(100),
    guarantor_phone  VARCHAR(15),
    principal        DECIMAL(12,2),
    tenure           INT,
    emi_amount       DECIMAL(12,2)
) ENGINE=InnoDB;

CREATE TABLE INSTALLMENT_SCHEDULE_2NF (
    loan_id          INT,
    installment_no   INT,
    due_date         DATE,
    principal_comp   DECIMAL(12,2),
    interest_comp    DECIMAL(12,2),
    amount_paid      DECIMAL(12,2),
    payment_date     DATE,
    PRIMARY KEY (loan_id, installment_no),
    FOREIGN KEY (loan_id) REFERENCES LOAN_INFO_2NF(loan_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Migrate data from LOAN_RAW into 2NF tables:
INSERT INTO LOAN_INFO_2NF
SELECT DISTINCT
    loan_id, applicant_name, applicant_email, applicant_pan, product_name,
    product_type, interest_rate, guarantor_name, guarantor_phone,
    principal, tenure, emi_amount
FROM LOAN_RAW;

INSERT INTO INSTALLMENT_SCHEDULE_2NF
SELECT 
    loan_id, installment_no, due_date, principal_comp, interest_comp,
    amount_paid, payment_date
FROM LOAN_RAW;


-- ----------------------------------------------------------------------------
-- STEP 3: THIRD NORMAL FORM (3NF)
-- Definition: A relation R is in 3NF if and only if:
--   1. It is in 2NF.
--   2. There are NO TRANSITIVE DEPENDENCIES of non-prime attributes on candidate keys.
-- Formal Codd Condition:
--   For every non-trivial functional dependency X -> Y:
--   EITHER:
--     a) X is a Superkey, OR
--     b) Y is a Prime Attribute (member of a candidate key).
--
-- Violations in LOAN_INFO_2NF:
-- Candidate Key of LOAN_INFO_2NF is {loan_id}.
--
-- Violation 1 (Applicant Transitive Dependency):
--   loan_id -> applicant_email
--   applicant_email -> {applicant_name, applicant_pan} (FD2)
--   Here, applicant_email is NOT a superkey of LOAN_INFO_2NF, and applicant_name is non-prime!
--
-- Violation 2 (Product Transitive Dependency):
--   loan_id -> product_name
--   product_name -> {product_type, interest_rate} (FD4)
--   Here, product_name is NOT a superkey of LOAN_INFO_2NF, and product_type is non-prime!
--
-- Violation 3 (Guarantor Details):
--   Guarantor phone and name should reside in an independent Guarantor entity.
--
-- 3NF Decomposition:
-- Decompose into distinct entity relations where every non-key attribute directly
-- depends on the primary key, the whole key, and nothing but the key:
-- 1. APPLICANT_3NF      (applicant_email [PK], applicant_name, applicant_pan [UQ])
-- 2. LOAN_PRODUCT_3NF   (product_name [PK], product_type, interest_rate)
-- 3. GUARANTOR_3NF      (guarantor_phone [PK], guarantor_name)
-- 4. LOAN_3NF           (loan_id [PK], applicant_email [FK], product_name [FK],
--                        guarantor_phone [FK], principal, tenure, emi_amount)
-- 5. EMI_SCHEDULE_3NF   (loan_id, installment_no [PK], due_date, principal_comp,
--                        interest_comp, amount_paid, payment_date)
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS EMI_SCHEDULE_3NF;
DROP TABLE IF EXISTS LOAN_3NF;
DROP TABLE IF EXISTS GUARANTOR_3NF;
DROP TABLE IF EXISTS LOAN_PRODUCT_3NF;
DROP TABLE IF EXISTS APPLICANT_3NF;

CREATE TABLE APPLICANT_3NF (
    applicant_email VARCHAR(100) PRIMARY KEY,
    applicant_name  VARCHAR(100) NOT NULL,
    applicant_pan   VARCHAR(10)  NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE LOAN_PRODUCT_3NF (
    product_name  VARCHAR(100) PRIMARY KEY,
    product_type  VARCHAR(30)  NOT NULL,
    interest_rate DECIMAL(5,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE GUARANTOR_3NF (
    guarantor_phone VARCHAR(15)  PRIMARY KEY,
    guarantor_name  VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE LOAN_3NF (
    loan_id         INT PRIMARY KEY,
    applicant_email VARCHAR(100) NOT NULL,
    product_name    VARCHAR(100) NOT NULL,
    guarantor_phone VARCHAR(15)  DEFAULT NULL,
    principal       DECIMAL(12,2) NOT NULL,
    tenure          INT NOT NULL,
    emi_amount      DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (applicant_email) REFERENCES APPLICANT_3NF(applicant_email),
    FOREIGN KEY (product_name)    REFERENCES LOAN_PRODUCT_3NF(product_name),
    FOREIGN KEY (guarantor_phone) REFERENCES GUARANTOR_3NF(guarantor_phone)
) ENGINE=InnoDB;

CREATE TABLE EMI_SCHEDULE_3NF (
    loan_id        INT NOT NULL,
    installment_no INT NOT NULL,
    due_date       DATE NOT NULL,
    principal_comp DECIMAL(12,2) NOT NULL,
    interest_comp  DECIMAL(12,2) NOT NULL,
    amount_paid    DECIMAL(12,2) DEFAULT NULL,
    payment_date   DATE DEFAULT NULL,
    PRIMARY KEY (loan_id, installment_no),
    FOREIGN KEY (loan_id) REFERENCES LOAN_3NF(loan_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Migrate data from 2NF to 3NF tables:
INSERT INTO APPLICANT_3NF
SELECT DISTINCT applicant_email, applicant_name, applicant_pan
FROM LOAN_INFO_2NF;

INSERT INTO LOAN_PRODUCT_3NF
SELECT DISTINCT product_name, product_type, interest_rate
FROM LOAN_INFO_2NF;

INSERT INTO GUARANTOR_3NF
SELECT DISTINCT guarantor_phone, guarantor_name
FROM LOAN_INFO_2NF
WHERE guarantor_phone IS NOT NULL;

INSERT INTO LOAN_3NF
SELECT 
    loan_id, applicant_email, product_name, guarantor_phone,
    principal, tenure, emi_amount
FROM LOAN_INFO_2NF;

INSERT INTO EMI_SCHEDULE_3NF
SELECT 
    loan_id, installment_no, due_date, principal_comp, interest_comp,
    amount_paid, payment_date
FROM INSTALLMENT_SCHEDULE_2NF;


-- ----------------------------------------------------------------------------
-- STEP 4: BOYCE-CODD NORMAL FORM (BCNF)
-- Definition: A relation R is in BCNF if and only if for every non-trivial
-- functional dependency X -> Y:
--   X MUST BE A SUPERKEY.
--
-- Notice the crucial difference from 3NF:
-- 3NF permits X to NOT be a superkey IF Y is a prime attribute.
-- BCNF completely removes this exception!
--
-- RIGOROUS ANALYSIS OF OUR 3NF RELATIONS UNDER BCNF:
--
-- 1. APPLICANT_3NF:
--    Candidate Keys: {applicant_email}, {applicant_pan}
--    Dependencies:
--      - FD2: applicant_email -> {applicant_name, applicant_pan}
--             Determinant {applicant_email} is a candidate key (SUPERKEY). -> HOLDS
--      - FD5: applicant_pan -> {applicant_name, applicant_email}
--             Determinant {applicant_pan} is an alternate candidate key (SUPERKEY). -> HOLDS
--    => APPLICANT_3NF is strictly in BCNF!
--
-- 2. LOAN_PRODUCT_3NF:
--    Candidate Key: {product_name}
--    Dependencies:
--      - FD4: product_name -> {product_type, interest_rate}
--             Determinant {product_name} is a candidate key (SUPERKEY). -> HOLDS
--    => LOAN_PRODUCT_3NF is strictly in BCNF!
--
-- 3. GUARANTOR_3NF:
--    Candidate Key: {guarantor_phone}
--    Dependencies: guarantor_phone -> guarantor_name
--    Determinant is a candidate key (SUPERKEY). -> HOLDS
--    => GUARANTOR_3NF is strictly in BCNF!
--
-- 4. LOAN_3NF:
--    Candidate Key: {loan_id}
--    Dependencies: loan_id -> {applicant_email, product_name, guarantor_phone, principal, tenure, emi_amount}
--    Determinant is a candidate key (SUPERKEY). -> HOLDS
--    => LOAN_3NF is strictly in BCNF!
--
-- 5. EMI_SCHEDULE_3NF:
--    Candidate Key: {loan_id, installment_no}
--    Dependencies: {loan_id, installment_no} -> {due_date, principal_comp, interest_comp, amount_paid, payment_date}
--    Determinant is a candidate key (SUPERKEY). -> HOLDS
--    => EMI_SCHEDULE_3NF is strictly in BCNF!
--
-- CONCLUSION:
-- Every determinant in every decomposed relation is a SUPERKEY.
-- Therefore, our 3NF decomposition is ALREADY IN BCNF!
-- ----------------------------------------------------------------------------


-- ============================================================================
-- SECTION 6: LOSSLESS JOIN & DEPENDENCY PRESERVATION PROOF
-- ============================================================================
/*
THEORETICAL VERIFICATION:
1. LOSSLESS JOIN PROPERTY:
   A decomposition D = {R1, R2} of relation R is lossless with respect to F if and only if:
       (R1 ∩ R2 -> R1) ∈ F+   OR   (R1 ∩ R2 -> R2) ∈ F+
   In our decomposition, every split was performed along an existing functional dependency
   whose left-hand side is a superkey of one of the resulting tables.
   Therefore, reconstructing LOAN_RAW via Natural Joins is mathematically guaranteed
   to produce EXACTLY the original relation with ZERO spurious tuples!

2. DEPENDENCY PRESERVATION:
   All original functional dependencies (FD1, FD2, FD3, FD4, FD5) can be verified
   within individual relations without computing joins across multiple tables:
   - FD1: Preserved in LOAN_3NF + foreign keys.
   - FD2 & FD5: Preserved in APPLICANT_3NF.
   - FD3: Preserved in EMI_SCHEDULE_3NF.
   - FD4: Preserved in LOAN_PRODUCT_3NF.
   Hence, our decomposition is 100% DEPENDENCY PRESERVING.
*/

-- SQL VERIFICATION QUERY: Reconstructing LOAN_RAW through Lossless Joins
-- This query returns the exact 18 columns of LOAN_RAW with identical cardinality:
SELECT 
    l.loan_id,
    a.applicant_name,
    a.applicant_email,
    a.applicant_pan,
    lp.product_name,
    lp.product_type,
    lp.interest_rate,
    g.guarantor_name,
    g.guarantor_phone,
    l.principal,
    l.tenure,
    l.emi_amount,
    es.installment_no,
    es.due_date,
    es.principal_comp,
    es.interest_comp,
    es.amount_paid,
    es.payment_date
FROM LOAN_3NF l
JOIN APPLICANT_3NF a       ON l.applicant_email = a.applicant_email
JOIN LOAN_PRODUCT_3NF lp   ON l.product_name = lp.product_name
LEFT JOIN GUARANTOR_3NF g  ON l.guarantor_phone = g.guarantor_phone
JOIN EMI_SCHEDULE_3NF es   ON l.loan_id = es.loan_id
ORDER BY l.loan_id, es.installment_no;


-- ============================================================================
-- SECTION 7: VIVA DEFENSE GUIDE & FREQUENTLY ASKED QUESTIONS
-- ============================================================================
/*
Q1: What is the main difference between 3NF and BCNF?
A1: 3NF permits a dependency X -> Y where X is NOT a superkey, provided that Y
    is a prime attribute (part of some candidate key).
    BCNF is strictly stronger: for ANY non-trivial FD X -> Y, X MUST be a superkey,
    with no exceptions for prime attributes.

Q2: Can any relational schema be decomposed into BCNF while preserving all dependencies?
A2: No! While a lossless-join decomposition into BCNF is ALWAYS achievable,
    dependency preservation is NOT always guaranteed in BCNF (e.g., relations with
    overlapping candidate keys like R(A, B, C) with FDs AB -> C and C -> B).
    In contrast, a lossless-join, dependency-preserving decomposition into 3NF is
    always mathematically guaranteed. In our bank loan system, however, BCNF is achieved
    WITH full dependency preservation.

Q3: Why does our production schema use surrogate keys (applicant_id, product_id, loan_id)
    instead of natural keys like applicant_email or pan_no?
A3: Natural keys like email addresses and PAN cards are alphanumeric strings (VARCHAR).
    Surrogate keys (INT / BIGINT AUTO_INCREMENT):
    1. Consume only 4 or 8 bytes in B-Tree index leaf nodes, maximizing buffer pool hit rates.
    2. Are immutable (never change), avoiding expensive CASCADE updates across millions of foreign key rows.
    3. Eliminate real-world identity exposure in URLs and external APIs.
    The natural keys are still protected with UNIQUE constraints to preserve domain integrity!

Q4: When would a database engineer deliberately DENORMALIZE a database?
A4: In Read-Heavy OLAP (Online Analytical Processing) systems, Data Warehouses,
    and Reporting Dashboards. Denormalization reduces expensive multi-table JOINs,
    pre-calculating aggregates to provide sub-second analytical queries, at the
    cost of write overhead and controlled redundancy managed via ETL batch jobs.
*/

-- ============================================================================
-- END OF NORMALIZATION FILE
-- ============================================================================
