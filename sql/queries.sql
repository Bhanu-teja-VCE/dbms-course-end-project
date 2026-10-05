-- ============================================================================
-- BANK LOAN MANAGEMENT SYSTEM: EMI PROCESSING, REPAYMENT TRACKING & RISK ASSESSMENT
-- Stage 4: Advanced SQL Queries, Relational Algebra & Analytical Views
-- Database: MySQL 8.0+ (InnoDB)
-- Database Name: bank_loan_db
-- ============================================================================

USE bank_loan_db;

-- ============================================================================
-- SECTION 1: BUSINESS & RISK ANALYTICAL VIEWS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- VIEW 1: overdue_emi_view
-- Purpose: Real-time operational view for loan officers and collection agents.
-- Consolidates all overdue installments along with borrower contact details,
-- loan product terms, accrued late penalties, and delinquency age in days.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW overdue_emi_view AS
SELECT 
    es.emi_id,
    es.loan_id,
    l.applicant_id,
    a.name AS applicant_name,
    a.phone AS applicant_phone,
    a.email AS applicant_email,
    lp.name AS product_name,
    lp.product_type,
    es.installment_no,
    es.due_date,
    DATEDIFF(CURRENT_DATE, es.due_date) AS days_overdue,
    es.principal_component,
    es.interest_component,
    es.emi_amount,
    es.penalty_amount,
    (es.emi_amount + es.penalty_amount) AS total_overdue_demand,
    es.status AS emi_status,
    l.status AS loan_status
FROM EMI_SCHEDULE es
JOIN LOAN l ON es.loan_id = l.loan_id
JOIN APPLICANT a ON l.applicant_id = a.applicant_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
WHERE es.status = 'OVERDUE';


-- ----------------------------------------------------------------------------
-- VIEW 2: loan_portfolio_summary_view
-- Purpose: Executive management summary providing high-level portfolio distribution,
-- total capital deployment, active exposures, default rates, and weighted pricing.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW loan_portfolio_summary_view AS
SELECT 
    lp.product_type,
    COUNT(DISTINCT l.loan_id) AS total_loans_count,
    COUNT(DISTINCT CASE WHEN l.status = 'ACTIVE' THEN l.loan_id END) AS active_loans_count,
    COUNT(DISTINCT CASE WHEN l.status = 'DEFAULTED' THEN l.loan_id END) AS defaulted_loans_count,
    COUNT(DISTINCT CASE WHEN l.status = 'CLOSED' THEN l.loan_id END) AS closed_loans_count,
    COALESCE(SUM(l.principal_amount), 0.00) AS total_principal_disbursed,
    COALESCE(SUM(CASE WHEN l.status = 'ACTIVE' THEN l.principal_amount ELSE 0.00 END), 0.00) AS active_principal_exposure,
    COALESCE(ROUND(AVG(l.interest_rate), 2), 0.00) AS avg_interest_rate
FROM LOAN_PRODUCT lp
LEFT JOIN LOAN l ON lp.product_id = l.product_id
GROUP BY lp.product_type;


-- ============================================================================
-- SECTION 2: ADVANCED ANALYTICAL AND OPERATIONAL QUERIES
-- ============================================================================

-- ============================================================================
-- QUERY 1: Overdue Loans Report (JOIN + GROUP BY + HAVING)
-- Business Objective: Identify all accounts with active default stress. Shows
-- applicant details, total sanctioned principal, total overdue count, and total
-- overdue monetary exposure (including penalties).
--
-- RELATIONAL ALGEBRA NOTATION:
-- OverdueInstallments = σ_{status = 'OVERDUE'}(EMI_SCHEDULE)
-- JoinedData = APPLICANT ⋈_{APPLICANT.applicant_id = LOAN.applicant_id} LOAN ⋈_{LOAN.loan_id = OverdueInstallments.loan_id} OverdueInstallments
-- GroupedData = γ_{applicant_id, name, phone, loan_id, principal_amount; COUNT(emi_id) → overdue_count, SUM(emi_amount + penalty_amount) → total_overdue_amount, MIN(due_date) → earliest_overdue_date}(JoinedData)
-- Result = π_{name, phone, loan_id, principal_amount, overdue_count, total_overdue_amount, earliest_overdue_date}(σ_{overdue_count ≥ 1}(GroupedData))
--
-- LaTeX Format:
-- \pi_{\text{name, phone, loan\_id, principal\_amount, overdue\_count, total\_overdue\_amount}} \left( 
--   \sigma_{\text{overdue\_count} \ge 1} \left( 
--     \gamma_{\text{applicant\_id, name, phone, loan\_id, principal\_amount}; \text{COUNT}(\text{emi\_id}) \to \text{overdue\_count}, \text{SUM}(\text{emi\_amount} + \text{penalty\_amount}) \to \text{total\_overdue\_amount}} \left( 
--       \text{APPLICANT} \bowtie \text{LOAN} \bowtie \sigma_{\text{status} = '\text{OVERDUE}'}(\text{EMI\_SCHEDULE}) 
--     \right) 
--   \right) 
-- \right)
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Why HAVING instead of WHERE for overdue_count?
--    WHERE filters rows BEFORE aggregation (we filter `es.status = 'OVERDUE'`),
--    whereas HAVING filters groups AFTER aggregation based on aggregate metrics (`COUNT(es.emi_id) >= 1`).
-- 2. Index Optimization: Requires composite index on `EMI_SCHEDULE(status, loan_id)`
--    to filter overdue records without scanning the entire multi-year schedule table.
-- ============================================================================
SELECT 
    a.applicant_id,
    a.name AS applicant_name,
    a.phone AS applicant_phone,
    l.loan_id,
    l.principal_amount AS loan_amount,
    COUNT(es.emi_id) AS overdue_count,
    SUM(es.emi_amount + es.penalty_amount) AS total_overdue_amount,
    MIN(es.due_date) AS earliest_overdue_date
FROM APPLICANT a
JOIN LOAN l ON a.applicant_id = l.applicant_id
JOIN EMI_SCHEDULE es ON l.loan_id = es.loan_id
WHERE es.status = 'OVERDUE'
GROUP BY 
    a.applicant_id,
    a.name, 
    a.phone, 
    l.loan_id, 
    l.principal_amount
HAVING COUNT(es.emi_id) >= 1
ORDER BY total_overdue_amount DESC;


-- ============================================================================
-- QUERY 2: Portfolio-wise Outstanding Amount (GROUP BY + HAVING)
-- Business Objective: Financial portfolio risk reporting. For each loan product
-- category (HOME, PERSONAL, VEHICLE, etc.), compute total sanctioned capital,
-- current outstanding unpaid principal, total cash collected via repayments,
-- and total active loan count.
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Avoiding Cartesian Fan-out: A direct JOIN between EMI_SCHEDULE and REPAYMENT
--    multiplies rows (M installments × N repayments per loan), causing gross
--    inflation of sums. We aggregate installments and repayments separately
--    via subqueries before joining back to the active loan portfolio.
-- 2. Outstanding Principal vs Balance After: Outstanding principal is accurately
--    defined as the sum of `principal_component` for all unserviced installments
--    ('PENDING', 'OVERDUE', 'PARTIALLY_PAID').
-- ============================================================================
SELECT 
    lp.product_type,
    COUNT(DISTINCT l.loan_id) AS active_loan_count,
    COALESCE(SUM(l.principal_amount), 0.00) AS total_disbursed,
    COALESCE(SUM(unpaid_sched.unpaid_principal), 0.00) AS total_outstanding_principal,
    COALESCE(SUM(repaid_sched.total_repaid), 0.00) AS total_collected
FROM LOAN_PRODUCT lp
JOIN LOAN l ON lp.product_id = l.product_id AND l.status = 'ACTIVE'
LEFT JOIN (
    SELECT 
        loan_id, 
        SUM(principal_component) AS unpaid_principal
    FROM EMI_SCHEDULE
    WHERE status IN ('PENDING', 'OVERDUE', 'PARTIALLY_PAID')
    GROUP BY loan_id
) unpaid_sched ON l.loan_id = unpaid_sched.loan_id
LEFT JOIN (
    SELECT 
        loan_id, 
        SUM(amount_paid) AS total_repaid
    FROM REPAYMENT
    GROUP BY loan_id
) repaid_sched ON l.loan_id = repaid_sched.loan_id
GROUP BY lp.product_type
HAVING active_loan_count > 0
ORDER BY total_disbursed DESC;


-- ============================================================================
-- QUERY 3: Defaulter List (Correlated Subquery)
-- Business Objective: In accordance with Reserve Bank of India (RBI) prudential
-- norms, an account with 3 or more consecutive overdue monthly installments
-- must be classified as a chronic default / Non-Performing Asset (NPA).
--
-- RELATIONAL ALGEBRA NOTATION:
-- Let O = σ_{status = 'OVERDUE'}(EMI_SCHEDULE)
-- Consecutive3 = π_{loan_id} (
--     O ⋈_{O.loan_id = O2.loan_id ∧ O2.installment_no = O.installment_no + 1} ρ_{O2}(O)
--       ⋈_{O.loan_id = O3.loan_id ∧ O3.installment_no = O.installment_no + 2} ρ_{O3}(O)
-- )
-- Result = π_{applicant_id, name, phone, pan_no, loan_id, principal_amount, status} (
--     APPLICANT ⋈ LOAN ⋈ Consecutive3
-- )
--
-- LaTeX Format:
-- O = \sigma_{\text{status} = '\text{OVERDUE}'}(\text{EMI\_SCHEDULE}) \\
-- C_3 = \pi_{\text{loan\_id}} \left( 
--   O \bowtie_{O.\text{loan\_id} = O_2.\text{loan\_id} \land O_2.\text{installment\_no} = O.\text{installment\_no} + 1} \rho_{O_2}(O) 
--     \bowtie_{O.\text{loan\_id} = O_3.\text{loan\_id} \land O_3.\text{installment\_no} = O.\text{installment\_no} + 2} \rho_{O_3}(O) 
-- \right) \\
-- \text{Result} = \pi_{\text{applicant\_id, name, phone, pan\_no, loan\_id, principal\_amount, status}} \left( 
--   \text{APPLICANT} \bowtie \text{LOAN} \bowtie C_3 
-- \right)
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Why Correlated Subquery?
--    A simple `COUNT(overdue) >= 3` would erroneously flag a borrower who missed
--    installments 2, 7, and 14 non-consecutively. The correlated subquery checks
--    for strict installment contiguity (k, k+1, k+2) scoped to the outer loan.
-- 2. Cost: O(N * M) execution where N is number of candidate loans and M is overdue installments.
--    Indexed by `(loan_id, installment_no, status)` to ensure index-only scans.
-- ============================================================================
SELECT 
    a.applicant_id,
    a.name AS applicant_name,
    a.phone AS applicant_phone,
    a.pan_no,
    l.loan_id,
    l.principal_amount,
    l.status AS loan_status
FROM APPLICANT a
JOIN LOAN l ON a.applicant_id = l.applicant_id
WHERE EXISTS (
    SELECT 1
    FROM EMI_SCHEDULE es1
    WHERE es1.loan_id = l.loan_id
      AND es1.status = 'OVERDUE'
      AND (
          SELECT COUNT(*)
          FROM EMI_SCHEDULE es2
          WHERE es2.loan_id = es1.loan_id
            AND es2.status = 'OVERDUE'
            AND es2.installment_no BETWEEN es1.installment_no AND es1.installment_no + 2
      ) = 3
)
ORDER BY a.applicant_id, l.loan_id;


-- ============================================================================
-- QUERY 4: EMI Collection Efficiency by Month (DATE_FORMAT + GROUP BY)
-- Business Objective: Track monthly cash collection performance:
-- Efficiency % = (Actual Repayments Collected / Scheduled EMI Demand) * 100.
-- Crucial for treasury liquidity management and recovery tracking.
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. `DATE_FORMAT(due_date, '%Y-%m')` groups scheduled obligations into monthly buckets.
-- 2. `NULLIF(due.total_amount_due, 0)` eliminates division-by-zero errors in case
--    of months with zero billings.
-- 3. Pre-aggregating repayments per due-month prevents cartesian product duplication.
-- ============================================================================
SELECT 
    due.billing_month,
    due.total_emis_due,
    due.total_amount_due,
    COALESCE(coll.total_amount_collected, 0.00) AS total_amount_collected,
    ROUND(
        (COALESCE(coll.total_amount_collected, 0.00) / NULLIF(due.total_amount_due, 0)) * 100, 
        2
    ) AS collection_efficiency_pct
FROM (
    SELECT 
        DATE_FORMAT(due_date, '%Y-%m') AS billing_month,
        COUNT(emi_id) AS total_emis_due,
        SUM(emi_amount) AS total_amount_due
    FROM EMI_SCHEDULE
    GROUP BY DATE_FORMAT(due_date, '%Y-%m')
) due
LEFT JOIN (
    SELECT 
        DATE_FORMAT(es.due_date, '%Y-%m') AS billing_month,
        SUM(r.amount_paid) AS total_amount_collected
    FROM REPAYMENT r
    JOIN EMI_SCHEDULE es ON r.emi_id = es.emi_id
    GROUP BY DATE_FORMAT(es.due_date, '%Y-%m')
) coll ON due.billing_month = coll.billing_month
GROUP BY due.billing_month, due.total_emis_due, due.total_amount_due, coll.total_amount_collected
ORDER BY due.billing_month ASC;


-- ============================================================================
-- QUERY 5: Loans with EMI Above Product-Type Average (Nested Correlated Subquery)
-- Business Objective: Identify high-ticket loan commitments that exceed the average
-- EMI installment across their peer loan category (e.g., Jumbo Home Loans or Luxury Car Loans).
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. The subquery is double-nested and correlated with the outer query via `lp.product_type`.
-- 2. Level 1 Subquery: Computes `AVG(l_sub.emi_amount)` for loans matching the outer product_type.
-- 3. Level 2 Inner Subquery: Dynamically discovers all `product_id` values under that `product_type`.
-- 4. Enables credit underwriters to assess debt servicing stress against category norms.
-- ============================================================================
SELECT 
    l.loan_id,
    a.name AS applicant_name,
    lp.name AS product_name,
    lp.product_type,
    l.principal_amount,
    l.emi_amount,
    (
        SELECT ROUND(AVG(l_sub.emi_amount), 2)
        FROM LOAN l_sub
        WHERE l_sub.product_id IN (
            SELECT lp_sub.product_id
            FROM LOAN_PRODUCT lp_sub
            WHERE lp_sub.product_type = lp.product_type
        )
    ) AS product_type_avg_emi,
    ROUND(l.emi_amount - (
        SELECT AVG(l_sub.emi_amount)
        FROM LOAN l_sub
        WHERE l_sub.product_id IN (
            SELECT lp_sub.product_id
            FROM LOAN_PRODUCT lp_sub
            WHERE lp_sub.product_type = lp.product_type
        )
    ), 2) AS excess_over_avg
FROM LOAN l
JOIN APPLICANT a ON l.applicant_id = a.applicant_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
WHERE l.emi_amount > (
    SELECT AVG(l_sub.emi_amount)
    FROM LOAN l_sub
    WHERE l_sub.product_id IN (
        SELECT lp_sub.product_id
        FROM LOAN_PRODUCT lp_sub
        WHERE lp_sub.product_type = lp.product_type
    )
)
ORDER BY lp.product_type, l.emi_amount DESC;


-- ============================================================================
-- QUERY 6: Applicants Who Applied But Have NO Active Loans (LEFT JOIN + IS NULL)
-- Business Objective: Target marketing & CRM query. Identifies applicants who
-- submitted formal applications in the past, but currently hold zero active loans
-- (their previous applications were either REJECTED, PENDING, or fully CLOSED).
--
-- RELATIONAL ALGEBRA NOTATION:
-- AppliedApplicants = π_{applicant_id}(LOAN)
-- ActiveApplicants = π_{applicant_id}(σ_{status = 'ACTIVE'}(LOAN))
-- InactiveApplicants = AppliedApplicants - ActiveApplicants
-- Result = π_{applicant_id, name, email, phone, annual_income, credit_score} (
--     APPLICANT ⋈ InactiveApplicants
-- )
--
-- LaTeX Format:
-- A_{\text{applied}} = \pi_{\text{applicant\_id}}(\text{LOAN}) \\
-- A_{\text{active}} = \pi_{\text{applicant\_id}}(\sigma_{\text{status} = '\text{ACTIVE}'}(\text{LOAN})) \\
-- A_{\text{target}} = A_{\text{applied}} - A_{\text{active}} \\
-- \text{Result} = \pi_{\text{applicant\_id, name, email, phone, annual\_income, credit\_score}} \left( 
--   \text{APPLICANT} \bowtie A_{\text{target}} 
-- \right)
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Anti-Join Pattern: In SQL, set difference (R - S) is classically implemented
--    using `LEFT JOIN ... WHERE right_table.PK IS NULL`.
-- 2. Joining `LOAN l_all` guarantees the applicant actually submitted an application.
--    The `LEFT JOIN LOAN l_active ... AND l_active.status = 'ACTIVE'` matches active loans.
--    The `WHERE l_active.loan_id IS NULL` filters out any applicant possessing an active loan.
-- ============================================================================
SELECT 
    a.applicant_id,
    a.name AS applicant_name,
    a.email,
    a.phone,
    a.annual_income,
    a.credit_score,
    COUNT(l_all.loan_id) AS total_past_applications
FROM APPLICANT a
JOIN LOAN l_all ON a.applicant_id = l_all.applicant_id
LEFT JOIN LOAN l_active ON a.applicant_id = l_active.applicant_id AND l_active.status = 'ACTIVE'
WHERE l_active.loan_id IS NULL
GROUP BY a.applicant_id, a.name, a.email, a.phone, a.annual_income, a.credit_score
ORDER BY a.applicant_id;


-- ============================================================================
-- QUERY 7: High-Risk Applicants (Credit Score & Leverage Stress Test)
-- Business Objective: Regulatory early warning indicator. Detects high-risk
-- borrowers who have poor credit bureau scores (< 600) AND whose total active
-- borrowing exceeds 500% of their verifiable annual gross income.
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Combines row-level filtering (`WHERE l.status = 'ACTIVE' AND a.credit_score < 600`)
--    with aggregate group filtering (`HAVING total_active_loan_amount > (5 * a.annual_income)`).
-- 2. `NULLIF(a.annual_income, 0)` protects against division-by-zero errors.
-- 3. Enables the bank's risk department to mandate additional collateral or invoke guarantor covenants.
-- ============================================================================
SELECT 
    a.applicant_id,
    a.name AS applicant_name,
    a.credit_score,
    a.annual_income,
    SUM(l.principal_amount) AS total_active_loan_amount,
    ROUND(SUM(l.principal_amount) / NULLIF(a.annual_income, 0), 2) AS debt_to_income_multiple,
    COUNT(l.loan_id) AS active_loan_count
FROM APPLICANT a
JOIN LOAN l ON a.applicant_id = l.applicant_id
WHERE l.status = 'ACTIVE'
  AND a.credit_score < 600
GROUP BY a.applicant_id, a.name, a.credit_score, a.annual_income
HAVING total_active_loan_amount > (5 * a.annual_income)
ORDER BY debt_to_income_multiple DESC;


-- ============================================================================
-- QUERY 8: UNION: Unified Active Stakeholder Risk Exposure View
-- Business Objective: Holistic legal & risk view. Merges primary borrowers and
-- third-party guarantors into a single legal stakeholder liability directory
-- for active loans.
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. UNION vs UNION ALL: UNION performs automatic duplicate elimination across
--    result sets, whereas UNION ALL preserves duplicates. Here, UNION guarantees
--    a clean, distinct stakeholder list.
-- 2. Tagging each row with literal 'PRIMARY_BORROWER' or 'GUARANTOR' enables
--    downstream recovery platforms to dispatch appropriate legal notices.
-- ============================================================================
SELECT 
    a.applicant_id AS stakeholder_id,
    a.name AS stakeholder_name,
    'PRIMARY_BORROWER' AS stakeholder_role,
    a.phone,
    a.pan_no,
    l.loan_id,
    lp.name AS product_name,
    l.principal_amount AS liability_amount,
    l.status AS loan_status
FROM APPLICANT a
JOIN LOAN l ON a.applicant_id = l.applicant_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
WHERE l.status = 'ACTIVE'

UNION

SELECT 
    g.guarantor_id AS stakeholder_id,
    g.name AS stakeholder_name,
    'GUARANTOR' AS stakeholder_role,
    g.phone,
    g.pan_no,
    l.loan_id,
    lp.name AS product_name,
    l.principal_amount AS liability_amount,
    l.status AS loan_status
FROM GUARANTOR g
JOIN LOAN l ON g.guarantor_id = l.guarantor_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
WHERE l.status = 'ACTIVE'

ORDER BY loan_id, stakeholder_role;


-- ============================================================================
-- QUERY 9: EXCEPT Equivalent: Borrowers Who Are NOT Guarantors
-- Business Objective: Find applicants who have taken loans as primary borrowers,
-- but have never acted as a guarantor for any third-party loan.
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. MySQL 8.0 historically lacked the `EXCEPT` / `MINUS` set operator (added in 8.0.31).
--    The universal, high-performance relational standard is the `LEFT JOIN ... WHERE right.PK IS NULL`
--    anti-semi-join pattern.
-- 2. Linkage: We match borrower identity to guarantor identity via `pan_no` (the Permanent Account
--    Number assigned by the Income Tax Department of India, which is globally unique per legal person).
-- 3. If an applicant's PAN does not appear in the GUARANTOR table, `g.guarantor_id IS NULL` evaluates to TRUE.
-- ============================================================================
SELECT DISTINCT 
    a.applicant_id,
    a.name AS applicant_name,
    a.pan_no,
    a.email,
    a.phone,
    a.annual_income,
    a.credit_score
FROM APPLICANT a
JOIN LOAN l ON a.applicant_id = l.applicant_id
LEFT JOIN GUARANTOR g ON a.pan_no = g.pan_no
WHERE g.guarantor_id IS NULL
ORDER BY a.applicant_id;


-- ============================================================================
-- QUERY 10: Aging Analysis (Delinquency Aging Buckets via CASE)
-- Business Objective: Standard banking aging schedule mandated by the RBI Master
-- Directions on Prudential Norms on Income Recognition, Asset Classification and
-- Provisioning (IRACP):
--   - 01 to 30 Days: SMA-0 (Special Mention Account 0 : Early stress)
--   - 31 to 60 Days: SMA-1 (Special Mention Account 1 : Sub-standard stress)
--   - 61 to 90 Days: SMA-2 (Special Mention Account 2 : Severe stress)
--   - 90+ Days     : NPA   (Non-Performing Asset : Statutory default)
--
-- VIVA DEFENSE & DESIGN DECISION:
-- 1. Uses `DATEDIFF(CURRENT_DATE, es.due_date)` to calculate exact aging elapsed.
-- 2. Aggregates both principal and accrued penalty components to report total demand.
-- 3. `CASE` expressions in both SELECT and GROUP BY categorize continuous day counts
--    into standard discrete regulatory provisioning tiers.
-- ============================================================================
SELECT 
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) <= 30 THEN '0-30 Days (SMA-0 : Early Stress)'
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) BETWEEN 31 AND 60 THEN '31-60 Days (SMA-1 : Medium Risk)'
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) BETWEEN 61 AND 90 THEN '61-90 Days (SMA-2 : High Risk)'
        ELSE '90+ Days (NPA : Non-Performing Asset)'
    END AS aging_bucket,
    COUNT(es.emi_id) AS total_overdue_installments,
    COUNT(DISTINCT es.loan_id) AS impacted_loans_count,
    SUM(es.principal_component) AS overdue_principal,
    SUM(es.interest_component) AS overdue_interest,
    SUM(es.penalty_amount) AS accrued_penalties,
    SUM(es.emi_amount + es.penalty_amount) AS total_overdue_demand
FROM EMI_SCHEDULE es
WHERE es.status = 'OVERDUE'
GROUP BY 
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) <= 30 THEN '0-30 Days (SMA-0 : Early Stress)'
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) BETWEEN 31 AND 60 THEN '31-60 Days (SMA-1 : Medium Risk)'
        WHEN DATEDIFF(CURRENT_DATE, es.due_date) BETWEEN 61 AND 90 THEN '61-90 Days (SMA-2 : High Risk)'
        ELSE '90+ Days (NPA : Non-Performing Asset)'
    END
ORDER BY MIN(DATEDIFF(CURRENT_DATE, es.due_date)) ASC;

-- ============================================================================
-- END OF QUERIES FILE
-- ============================================================================
