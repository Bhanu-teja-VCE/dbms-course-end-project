#!/usr/bin/env python3
"""
================================================================================
Bank Loan Management System: EMI Processing, Repayment Tracking, and Risk Assessment
Data Generation Script (generate_seed.py)
================================================================================
B.Tech CSE Database Management Systems Course Project
Database Target: MySQL 8.0+ (InnoDB Storage Engine)

PURPOSE:
--------
This script deterministically generates synthetic, production-grade sample data
for the Bank Loan Management System and outputs a complete, ready-to-execute
seed SQL script at `sql/seed.sql`.

VIVA / EXAM DEFENSE GUIDE:
--------------------------
1. Why Faker with 'en_IN' locale & Seed=42?
   - Indian Context: Generates culturally accurate Indian applicant and guarantor
     names, addresses, and phone numbers suited for an Indian banking context
     (e.g., State Bank of India / HDFC style operational model).
   - Deterministic Reproducibility: Setting `seed=42` ensures that every run
     produces identical primary keys, amounts, and dates. This guarantees reproducible
     grading, test assertions, and query outputs for evaluators.

2. Reducing Balance EMI Amortization Formula:
   - EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
     where:
       P = Principal loan amount (INR)
       r = Monthly interest rate = (Annual Interest Rate % / 100) / 12
       n = Loan tenure in months
   - Why not Flat Rate? In Indian commercial banks regulated by RBI, all retail
     and commercial loans are amortized using the reducing balance method.
     Interest for month k is computed on the remaining principal balance B_{k-1}:
       Interest_k  = round(B_{k-1} * r, 2)
       Principal_k = round(EMI - Interest_k, 2)
       B_k         = round(B_{k-1} - Principal_k, 2)
     In the final installment (k = n), the remaining balance is paid off exactly,
     ensuring balance_after reaches 0.00 without floating-point rounding drift.

3. RBI Regulatory Alignment:
   - CIBIL / Credit Scores: 300 to 900 scale. Applicants with >= 750 receive prime
     interest rates; < 650 are flagged for higher risk, guarantor requirements,
     or loan rejection.
   - Non-Performing Asset (NPA) Classification: Under RBI prudential guidelines,
     overdue loans progress through SMA-0 (1-30 days), SMA-1 (31-60 days),
     SMA-2 (61-90 days), and become NPAs (DEFAULTED) after 90 days.
   - Default Resolution: Actions in DEFAULT_LOG reflect legal tools available to
     Indian banks, including SARFAESI Act Section 13(2) notices, Section 13(4)
     possession / asset seizure, debt restructuring, and One-Time Settlements (OTS).

ENTITIES GENERATED:
-------------------
1. APPLICANT (80 records)
2. LOAN_PRODUCT (10 standard bank products)
3. GUARANTOR (40 records)
4. LOAN (120 loans: 60 ACTIVE, 20 CLOSED, 15 DEFAULTED, 10 APPROVED, 10 PENDING, 5 REJECTED)
5. EMI_SCHEDULE (Full schedules for all 80 ACTIVE and CLOSED loans)
6. REPAYMENT (200 repayment transactions for PAID and PARTIALLY_PAID EMIs)
7. DEFAULT_LOG (30 recovery tracking entries for DEFAULTED loans)
8. LOAN_AUDIT (25 historical system audit trail records)

OUTPUT FILE:
------------
`sql/seed.sql`
================================================================================
"""

import os
import random
import string
from datetime import datetime, date, timedelta
from faker import Faker

# ------------------------------------------------------------------------------
# 1. Deterministic Seeding for Reproducibility
# ------------------------------------------------------------------------------
RANDOM_SEED = 42
random.seed(RANDOM_SEED)
Faker.seed(RANDOM_SEED)

fake = Faker('en_IN')

# Simulation Cutoff Reference Date (Simulated "Current Banking Date")
SIMULATION_CURRENT_DATE = date(2024, 10, 1)


# ------------------------------------------------------------------------------
# 2. Date & Financial Utility Functions
# ------------------------------------------------------------------------------
def add_months(source_date: date, months: int) -> date:
    """
    Safely adds a given number of calendar months to a date, handling month-end
    boundaries and leap years (e.g., Jan 31 + 1 month = Feb 28/29).
    """
    month_index = source_date.month - 1 + months
    year = source_date.year + month_index // 12
    month = month_index % 12 + 1
    
    # Days in month lookup
    is_leap = (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0))
    days_in_month = [31, 29 if is_leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    day = min(source_date.day, days_in_month[month - 1])
    return date(year, month, day)


def calculate_reducing_balance_schedule(principal: float, annual_rate: float, tenure_months: int, start_date: date):
    """
    Computes standard reducing-balance EMI and installment breakdown:
    EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
    
    Returns:
        base_emi: Monthly EMI rounded to 2 decimal places
        total_payable: Exact sum of all installments
        schedule: List of installment dictionaries with:
                  (installment_no, due_date, principal_comp, interest_comp,
                   emi_amount, balance_after)
    """
    P = float(principal)
    r = (float(annual_rate) / 100.0) / 12.0
    n = int(tenure_months)

    if r <= 0:
        base_emi = round(P / n, 2)
    else:
        # Standard annuity EMI formula
        numerator = P * r * ((1.0 + r) ** n)
        denominator = ((1.0 + r) ** n) - 1.0
        base_emi = round(numerator / denominator, 2)

    schedule = []
    current_balance = P

    for m in range(1, n + 1):
        due_date = add_months(start_date, m)
        interest_comp = round(current_balance * r, 2)

        if m == n:
            # Final installment pays off exactly the remaining balance
            principal_comp = round(current_balance, 2)
            row_emi = round(principal_comp + interest_comp, 2)
            balance_after = 0.00
        else:
            principal_comp = round(base_emi - interest_comp, 2)
            if principal_comp > current_balance:
                principal_comp = round(current_balance, 2)
                row_emi = round(principal_comp + interest_comp, 2)
                balance_after = 0.00
            else:
                balance_after = round(current_balance - principal_comp, 2)
                row_emi = round(principal_comp + interest_comp, 2)

        current_balance = balance_after

        schedule.append({
            'installment_no': m,
            'due_date': due_date,
            'principal_component': principal_comp,
            'interest_component': interest_comp,
            'emi_amount': row_emi,
            'balance_after': balance_after
        })

    total_payable = round(sum(item['emi_amount'] for item in schedule), 2)
    return base_emi, total_payable, schedule


def sql_format(val) -> str:
    """Formats Python types into MySQL-safe literals."""
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        return f"{val:.2f}"
    if isinstance(val, (date, datetime)):
        if isinstance(val, datetime):
            return f"'{val.strftime('%Y-%m-%d %H:%M:%S')}'"
        return f"'{val.strftime('%Y-%m-%d')}'"
    
    # Text escaping (single quotes)
    clean_str = str(val).replace("'", "''")
    return f"'{clean_str}'"


def clean_person_name(name_raw: str) -> str:
    """Removes honorific prefixes (Dr., Mr., Mrs.) for clean Indian personal names."""
    prefixes = ['Dr. ', 'Mr. ', 'Mrs. ', 'Miss ', 'Prof. ', 'Shri ', 'Smt. ']
    cleaned = name_raw
    for p in prefixes:
        if cleaned.startswith(p):
            cleaned = cleaned[len(p):]
    return cleaned.strip()


def generate_pan(first_name: str, last_name: str, unique_seq: int) -> str:
    """
    Generates realistic 10-character Indian Permanent Account Number (PAN):
    - Chars 1-3: Random uppercase alphabets (AAA - ZZZ)
    - Char 4: 'P' (Person / Individual)
    - Char 5: First letter of applicant's surname (or first name if surname missing)
    - Chars 6-9: 4 digits (0001 - 9999)
    - Char 10: Check letter (A - Z)
    """
    c1_3 = "".join(random.choices(string.ascii_uppercase, k=3))
    status_char = 'P'
    surname_initial = last_name[0].upper() if last_name else 'S'
    digits_part = f"{unique_seq:04d}"
    check_char = random.choice(string.ascii_uppercase)
    return f"{c1_3}{status_char}{surname_initial}{digits_part}{check_char}"


# ------------------------------------------------------------------------------
# 3. Seed Generation Engine
# ------------------------------------------------------------------------------
def generate_seed():
    print("=" * 70)
    print("Bank Loan Management System - Seed Data Generation")
    print("=" * 70)

    # Output paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sql_dir = os.path.abspath(os.path.join(script_dir, '..', 'sql'))
    os.makedirs(sql_dir, exist_ok=True)
    out_file = os.path.join(sql_dir, 'seed.sql')

    # --------------------------------------------------------------------------
    # Master Reference: 10 Loan Products
    # --------------------------------------------------------------------------
    loan_products_spec = [
        {
            'product_id': 1,
            'name': 'Home Loan',
            'product_type': 'HOME',
            'interest_rate': 8.50,
            'min_amount': 500000.00,
            'max_amount': 5000000.00,
            'min_tenure_months': 60,
            'max_tenure_months': 360,
            'processing_fee_pct': 0.50,
            'penalty_rate_pct': 2.00,
            'description': 'Housing finance for purchase, construction, or extension of residential property.'
        },
        {
            'product_id': 2,
            'name': 'Personal Loan',
            'product_type': 'PERSONAL',
            'interest_rate': 12.00,
            'min_amount': 50000.00,
            'max_amount': 1500000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 60,
            'processing_fee_pct': 1.50,
            'penalty_rate_pct': 2.50,
            'description': 'Unsecured multipurpose personal credit for wedding, medical, travel, or emergency needs.'
        },
        {
            'product_id': 3,
            'name': 'Vehicle Loan',
            'product_type': 'VEHICLE',
            'interest_rate': 9.50,
            'min_amount': 100000.00,
            'max_amount': 3000000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 84,
            'processing_fee_pct': 1.00,
            'penalty_rate_pct': 2.00,
            'description': 'Automobile term financing for new and certified pre-owned passenger cars.'
        },
        {
            'product_id': 4,
            'name': 'Education Loan',
            'product_type': 'EDUCATION',
            'interest_rate': 7.00,
            'min_amount': 100000.00,
            'max_amount': 4000000.00,
            'min_tenure_months': 24,
            'max_tenure_months': 180,
            'processing_fee_pct': 0.00,
            'penalty_rate_pct': 1.50,
            'description': 'Subsidized education loans for premier university courses in India and abroad.'
        },
        {
            'product_id': 5,
            'name': 'Business Loan',
            'product_type': 'BUSINESS',
            'interest_rate': 11.00,
            'min_amount': 200000.00,
            'max_amount': 5000000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 120,
            'processing_fee_pct': 1.25,
            'penalty_rate_pct': 2.50,
            'description': 'Working capital and term credit for enterprise growth, inventory, and MSME machinery.'
        },
        {
            'product_id': 6,
            'name': 'Gold Loan',
            'product_type': 'GOLD',
            'interest_rate': 8.00,
            'min_amount': 50000.00,
            'max_amount': 2500000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 36,
            'processing_fee_pct': 0.50,
            'penalty_rate_pct': 2.00,
            'description': 'Instant liquidity secured against pledge of hallmark gold jewellery and coins.'
        },
        {
            'product_id': 7,
            'name': 'Agriculture Loan',
            'product_type': 'AGRICULTURE',
            'interest_rate': 6.00,
            'min_amount': 50000.00,
            'max_amount': 2000000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 84,
            'processing_fee_pct': 0.25,
            'penalty_rate_pct': 1.00,
            'description': 'Priority sector lending for farming equipment, crop inputs, and micro-irrigation.'
        },
        {
            'product_id': 8,
            'name': 'Home Renovation',
            'product_type': 'HOME',
            'interest_rate': 10.50,
            'min_amount': 100000.00,
            'max_amount': 2500000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 120,
            'processing_fee_pct': 1.00,
            'penalty_rate_pct': 2.00,
            'description': 'Home improvement finance for interior decoration, remodeling, and structural repairs.'
        },
        {
            'product_id': 9,
            'name': 'Two-Wheeler Loan',
            'product_type': 'VEHICLE',
            'interest_rate': 14.00,
            'min_amount': 50000.00,
            'max_amount': 300000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 48,
            'processing_fee_pct': 2.00,
            'penalty_rate_pct': 3.00,
            'description': 'Affordable financing for commuter motorcycles, scooters, and electric two-wheelers.'
        },
        {
            'product_id': 10,
            'name': 'Overdraft Facility',
            'product_type': 'BUSINESS',
            'interest_rate': 15.00,
            'min_amount': 100000.00,
            'max_amount': 3000000.00,
            'min_tenure_months': 12,
            'max_tenure_months': 60,
            'processing_fee_pct': 1.50,
            'penalty_rate_pct': 3.00,
            'description': 'Revolving overdraft line against business current account for operational cash flow.'
        }
    ]

    # Pre-defined prominent Indian employers
    salaried_employers = [
        'Tata Consultancy Services', 'Infosys Limited', 'HDFC Bank', 'Reliance Industries',
        'Wipro Technologies', 'Larsen & Toubro', 'State Bank of India', 'ICICI Bank',
        'Bharti Airtel', 'HCL Technologies', 'Tech Mahindra', 'Mahindra & Mahindra',
        'Cognizant Technology Solutions', 'Axis Bank', 'Maruti Suzuki India'
    ]
    govt_employers = [
        'Ministry of Railways', 'Defence Research & Development Organisation (DRDO)',
        'Bharat Heavy Electricals Limited (BHEL)', 'Oil and Natural Gas Corporation (ONGC)',
        'Delhi Development Authority', 'Life Insurance Corporation (LIC)'
    ]
    business_firms = [
        'Apex Enterprises', 'Krishna Traders & Logistics', 'Shree Ganesh Exports',
        'Vanguard Retail Solutions', 'Siddhi Vinayak Steels', 'Balaji Agro Commodities',
        'Mehta Textile Mills'
    ]
    professional_firms = [
        'Apollo Hospitals Healthcare', 'High Court of Delhi - Senior Chambers',
        'Deloitte India Consulting', 'PwC India Advisory', 'Kedia Tax Consultancy'
    ]

    # --------------------------------------------------------------------------
    # 4. Generate 80 APPLICANT Records
    # --------------------------------------------------------------------------
    print("Generating 80 APPLICANT records...")
    applicants = []
    used_emails = set()
    used_pans = set()
    used_aadhaars = set()

    for app_id in range(1, 81):
        raw_name = fake.name()
        name = clean_person_name(raw_name)
        name_parts = name.split()
        first_name = name_parts[0]
        last_name = name_parts[-1] if len(name_parts) > 1 else "Kumar"

        # Unique Email
        clean_first = "".join(filter(str.isalnum, first_name.lower()))
        clean_last = "".join(filter(str.isalnum, last_name.lower()))
        email_candidate = f"{clean_first}.{clean_last}{app_id}@gmail.com"
        while email_candidate in used_emails:
            email_candidate = f"{clean_first}.{clean_last}{app_id}_{random.randint(10, 99)}@gmail.com"
        used_emails.add(email_candidate)

        # Phone: Indian 10-digit mobile
        phone = f"+91 {random.choice([7, 8, 9])}{random.randint(100000000, 999999999)}"

        # Realistic Indian Address
        street = fake.street_address().replace('\n', ', ')
        city = fake.city()
        postcode = random.randint(110001, 700099)
        address = f"{street}, {city} - {postcode}"

        # Date of Birth (Age between 22 and 58 years)
        dob = fake.date_of_birth(minimum_age=22, maximum_age=58)

        # PAN Number (Unique, Format: ABCPD1234E)
        pan_num = generate_pan(first_name, last_name, 1000 + app_id)
        while pan_num in used_pans:
            pan_num = generate_pan(first_name, last_name, random.randint(1000, 9999))
        used_pans.add(pan_num)

        # Aadhaar Number (12 digits, unique, starting with 2-9)
        aadhaar_candidate = f"{random.randint(2000, 9999)}{random.randint(1000, 9999)}{app_id:04d}"
        while aadhaar_candidate in used_aadhaars:
            aadhaar_candidate = f"{random.randint(2000, 9999)}{random.randint(1000, 9999)}{random.randint(1000, 9999)}"
        used_aadhaars.add(aadhaar_candidate)

        # Annual Income (Range: ₹2,00,000 to ₹50,00,000)
        # Realistic distribution: entry, middle, upper-middle, high income
        income_tier = random.random()
        if income_tier < 0.40:
            income = random.randint(20, 80) * 10000.0  # 2L - 8L
        elif income_tier < 0.75:
            income = random.randint(81, 180) * 10000.0  # 8.1L - 18L
        elif income_tier < 0.90:
            income = random.randint(181, 320) * 10000.0  # 18.1L - 32L
        else:
            income = random.randint(321, 500) * 10000.0  # 32.1L - 50L

        # Credit Score (Range: 350 to 850)
        # 50% Prime (750-850), 30% Good (650-749), 15% Subprime (500-649), 5% High Risk (350-499)
        score_rand = random.random()
        if score_rand < 0.50:
            credit_score = random.randint(750, 850)
        elif score_rand < 0.80:
            credit_score = random.randint(650, 749)
        elif score_rand < 0.95:
            credit_score = random.randint(500, 649)
        else:
            credit_score = random.randint(350, 499)

        # Employment Type & Employer
        emp_rand = random.random()
        if emp_rand < 0.50:
            employment_type = 'SALARIED'
            employer_name = random.choice(salaried_employers)
        elif emp_rand < 0.70:
            employment_type = 'SELF_EMPLOYED'
            employer_name = f"{last_name} Enterprises & Consultancy"
        elif emp_rand < 0.85:
            employment_type = 'BUSINESS'
            employer_name = random.choice(business_firms)
        elif emp_rand < 0.93:
            employment_type = 'GOVERNMENT'
            employer_name = random.choice(govt_employers)
        else:
            employment_type = 'PROFESSIONAL'
            employer_name = random.choice(professional_firms)

        # Registration created_at between 2021-01-01 and 2023-12-31
        created_dt = fake.date_time_between(start_date=datetime(2021, 1, 1), end_date=datetime(2023, 12, 31))

        applicants.append({
            'applicant_id': app_id,
            'name': name,
            'email': email_candidate,
            'phone': phone,
            'address': address,
            'dob': dob,
            'pan_no': pan_num,
            'aadhaar_no': aadhaar_candidate,
            'annual_income': income,
            'credit_score': credit_score,
            'employment_type': employment_type,
            'employer_name': employer_name,
            'created_at': created_dt
        })

    # --------------------------------------------------------------------------
    # 5. Generate 40 GUARANTOR Records
    # --------------------------------------------------------------------------
    print("Generating 40 GUARANTOR records...")
    guarantors = []
    relationships = [
        'Father', 'Mother', 'Brother', 'Sister', 'Spouse',
        'Friend', 'Colleague', 'Business Partner', 'Uncle'
    ]

    for guar_id in range(1, 41):
        raw_name = fake.name()
        name = clean_person_name(raw_name)
        name_parts = name.split()
        first_name = name_parts[0]
        last_name = name_parts[-1] if len(name_parts) > 1 else "Verma"

        phone = f"+91 {random.choice([7, 8, 9])}{random.randint(100000000, 999999999)}"
        pan_num = generate_pan(first_name, last_name, 5000 + guar_id)
        while pan_num in used_pans:
            pan_num = generate_pan(first_name, last_name, random.randint(5000, 9999))
        used_pans.add(pan_num)

        relationship = random.choice(relationships)
        annual_income = random.randint(30, 400) * 10000.0  # ₹3L - ₹40L

        street = fake.street_address().replace('\n', ', ')
        city = fake.city()
        postcode = random.randint(110001, 700099)
        address = f"{street}, {city} - {postcode}"

        guarantors.append({
            'guarantor_id': guar_id,
            'name': name,
            'phone': phone,
            'pan_no': pan_num,
            'relationship': relationship,
            'annual_income': annual_income,
            'address': address
        })

    # --------------------------------------------------------------------------
    # 6. Generate 120 LOAN Records
    # Distribution:
    #   60 ACTIVE, 20 CLOSED, 15 DEFAULTED, 10 APPROVED, 10 PENDING, 5 REJECTED
    # --------------------------------------------------------------------------
    print("Generating 120 LOAN records (60 ACTIVE, 20 CLOSED, 15 DEFAULTED, 10 APPROVED, 10 PENDING, 5 REJECTED)...")
    
    # Establish ordered list of target statuses
    loan_statuses = (
        ['ACTIVE'] * 60 +
        ['CLOSED'] * 20 +
        ['DEFAULTED'] * 15 +
        ['APPROVED'] * 10 +
        ['PENDING'] * 10 +
        ['REJECTED'] * 5
    )
    # Shuffle deterministically to mix statuses across loan IDs
    random.shuffle(loan_statuses)

    bank_approvers = [
        'S. K. Verma (Chief Manager)',
        'Ananya Deshmukh (Asst. General Manager)',
        'Rameshwar Prasad (Senior Credit Manager)',
        'Pooja Sundaram (Zonal Credit Head)',
        'Vikramaditya Rao (Branch Operations Head)',
        'Meenakshi Sundaram (Credit Appraisal Desk)'
    ]

    # Map applicants by credit profile for realistic banking approval/rejection
    prime_applicants = [a for a in applicants if a['credit_score'] >= 700]
    moderate_applicants = [a for a in applicants if 600 <= a['credit_score'] < 700]
    high_risk_applicants = [a for a in applicants if a['credit_score'] < 600]

    loans = []
    
    for loan_id in range(1, 121):
        status = loan_statuses[loan_id - 1]

        # Select Product (round-robin / balanced spread)
        product_spec = loan_products_spec[(loan_id - 1) % len(loan_products_spec)]
        product_id = product_spec['product_id']
        interest_rate = product_spec['interest_rate']

        # Select Applicant matching risk profile
        if status in ('ACTIVE', 'CLOSED'):
            # Good credit standing
            applicant = random.choice(prime_applicants if prime_applicants else applicants)
        elif status == 'APPROVED':
            # Prime or moderate credit
            applicant = random.choice(prime_applicants + moderate_applicants)
        elif status == 'DEFAULTED':
            # Tend towards moderate or subprime
            applicant = random.choice(moderate_applicants + high_risk_applicants)
        elif status == 'REJECTED':
            # Subprime or high risk
            applicant = random.choice(high_risk_applicants if high_risk_applicants else applicants)
        else:  # PENDING
            applicant = random.choice(applicants)

        applicant_id = applicant['applicant_id']

        # Determine Principal Amount within product limits (round figures)
        min_amt = product_spec['min_amount']
        max_amt = product_spec['max_amount']
        # Sample realistic step-based amounts
        step = 50000.0 if max_amt >= 500000.0 else 10000.0
        steps_count = int((max_amt - min_amt) / step)
        principal = min_amt + (random.randint(0, max(0, steps_count)) * step)
        principal = min(principal, max_amt)

        # Determine Tenure (months)
        min_ten = product_spec['min_tenure_months']
        max_ten = product_spec['max_tenure_months']
        
        if status == 'CLOSED':
            # Closed loans must have completed all installments before current date
            # Keep tenure short to medium (12 to 36 months)
            possible_tenures = [t for t in [12, 18, 24, 36] if min_ten <= t <= max_ten]
            tenure_months = random.choice(possible_tenures) if possible_tenures else min_ten
        else:
            # Common banking tenure steps
            standard_tenures = [12, 24, 36, 48, 60, 84, 120, 180, 240, 300, 360]
            valid_tenures = [t for t in standard_tenures if min_ten <= t <= max_ten]
            tenure_months = random.choice(valid_tenures) if valid_tenures else min_ten

        # Assign Guarantor (required for high principal, education loans, or subprime score)
        needs_guarantor = (
            principal >= 1500000.0 or
            product_spec['product_type'] == 'EDUCATION' or
            applicant['credit_score'] < 680 or
            random.random() < 0.35
        )
        guarantor_id = random.randint(1, 40) if needs_guarantor else None

        # Calculate EMI and total payable using standard formula
        base_emi, total_payable, _ = calculate_reducing_balance_schedule(
            principal=principal,
            annual_rate=interest_rate,
            tenure_months=tenure_months,
            start_date=SIMULATION_CURRENT_DATE
        )

        # Dates and Lifecycle
        if status == 'CLOSED':
            # Disbursed long enough ago that tenure has fully passed
            # E.g., disbursed between 2021-01-15 and 2022-06-30
            disb_year = random.choice([2021, 2022])
            disb_month = random.randint(1, 6)
            disb_day = random.randint(1, 25)
            disbursement_date = date(disb_year, disb_month, disb_day)
            created_at = datetime.combine(disbursement_date - timedelta(days=random.randint(7, 14)), datetime.min.time())
            maturity_date = add_months(disbursement_date, tenure_months)
            approved_by = random.choice(bank_approvers)
            remarks = 'Loan fully repaid in adherence to schedule; No Dues Certificate (NDC) issued.'

        elif status == 'ACTIVE':
            # Disbursed 3 to 24 months ago; maturity is in the future
            months_ago = random.randint(3, min(24, tenure_months - 1))
            disbursement_date = add_months(SIMULATION_CURRENT_DATE, -months_ago)
            # Ensure day is consistent (e.g., 5th, 10th, 15th, or 20th of the month)
            disb_day = random.choice([5, 10, 15, 20])
            disbursement_date = date(disbursement_date.year, disbursement_date.month, disb_day)
            created_at = datetime.combine(disbursement_date - timedelta(days=random.randint(5, 12)), datetime.min.time())
            maturity_date = add_months(disbursement_date, tenure_months)
            approved_by = random.choice(bank_approvers)
            remarks = 'Regular account servicing via automated NACH mandate; asset performing (Standard).'

        elif status == 'DEFAULTED':
            # Disbursed 12 to 24 months ago; payments stopped 3 to 9 months ago
            months_ago = random.randint(12, 24)
            disbursement_date = add_months(SIMULATION_CURRENT_DATE, -months_ago)
            disb_day = random.choice([5, 10, 15])
            disbursement_date = date(disbursement_date.year, disbursement_date.month, disb_day)
            created_at = datetime.combine(disbursement_date - timedelta(days=random.randint(6, 15)), datetime.min.time())
            maturity_date = add_months(disbursement_date, tenure_months)
            approved_by = random.choice(bank_approvers)
            remarks = 'Account classified as Non-Performing Asset (NPA > 90 DPD); legal recovery underway.'

        elif status == 'APPROVED':
            # Recently approved, awaiting borrower acceptance or disbursement
            created_at = datetime.combine(SIMULATION_CURRENT_DATE - timedelta(days=random.randint(10, 25)), datetime.min.time())
            disbursement_date = None
            maturity_date = None
            approved_by = random.choice(bank_approvers)
            remarks = 'Sanction letter generated; pending disbursement pending loan agreement execution.'

        elif status == 'PENDING':
            # Application in review
            created_at = datetime.combine(SIMULATION_CURRENT_DATE - timedelta(days=random.randint(1, 15)), datetime.min.time())
            disbursement_date = None
            maturity_date = None
            approved_by = None
            remarks = 'Application under KYC, income, and legal property verification by appraisal committee.'

        elif status == 'REJECTED':
            # Application rejected
            created_at = datetime.combine(SIMULATION_CURRENT_DATE - timedelta(days=random.randint(15, 45)), datetime.min.time())
            disbursement_date = None
            maturity_date = None
            approved_by = 'Credit Underwriting Desk'
            remarks = 'Application declined: Credit score below cutoff / Insufficient debt-service coverage ratio.'

        loans.append({
            'loan_id': loan_id,
            'applicant_id': applicant_id,
            'product_id': product_id,
            'guarantor_id': guarantor_id,
            'principal_amount': principal,
            'interest_rate': interest_rate,
            'tenure_months': tenure_months,
            'emi_amount': base_emi,
            'total_payable': total_payable,
            'disbursement_date': disbursement_date,
            'maturity_date': maturity_date,
            'status': status,
            'approved_by': approved_by,
            'remarks': remarks,
            'created_at': created_at
        })

    # --------------------------------------------------------------------------
    # 7. Generate Full EMI_SCHEDULE for ACTIVE & CLOSED Loans
    # --------------------------------------------------------------------------
    print("Generating full EMI_SCHEDULE for all 60 ACTIVE and 20 CLOSED loans...")
    emi_schedules = []
    global_emi_id = 1

    # Keep references to paid & partially paid EMIs for generating repayments
    paid_or_partial_emis = []

    for loan in loans:
        if loan['status'] not in ('ACTIVE', 'CLOSED'):
            continue

        l_id = loan['loan_id']
        principal = loan['principal_amount']
        rate = loan['interest_rate']
        tenure = loan['tenure_months']
        start_date = loan['disbursement_date']
        is_closed = (loan['status'] == 'CLOSED')

        # Generate amortization table
        _, _, amort_rows = calculate_reducing_balance_schedule(
            principal=principal,
            annual_rate=rate,
            tenure_months=tenure,
            start_date=start_date
        )

        for row in amort_rows:
            due_date = row['due_date']
            p_comp = row['principal_component']
            i_comp = row['interest_component']
            emi_amt = row['emi_amount']
            bal_after = row['balance_after']

            if is_closed:
                # All closed loan installments were fully settled
                inst_status = 'PAID'
                # Payment was made on due date or slightly early/late (-3 to +2 days)
                paid_date = due_date + timedelta(days=random.choice([-3, -2, -1, 0, 1, 2]))
                penalty = 0.00
            else:
                # ACTIVE loan: status depends on due_date vs simulation current date
                if due_date < SIMULATION_CURRENT_DATE:
                    # Past installments: mostly PAID, a few OVERDUE, few PARTIALLY_PAID
                    time_diff_days = (SIMULATION_CURRENT_DATE - due_date).days
                    if time_diff_days > 45:
                        # Older installments: settled
                        inst_status = 'PAID'
                        paid_date = due_date + timedelta(days=random.choice([-2, -1, 0, 1, 2]))
                        penalty = 0.00
                    else:
                        # Recent installments (within last 45 days)
                        r_state = random.random()
                        if r_state < 0.75:
                            inst_status = 'PAID'
                            paid_date = due_date + timedelta(days=random.choice([-1, 0, 1, 2]))
                            penalty = 0.00
                        elif r_state < 0.90:
                            inst_status = 'OVERDUE'
                            paid_date = None
                            penalty = round(max(250.00, emi_amt * 0.02), 2)  # 2% late penalty
                        else:
                            inst_status = 'PARTIALLY_PAID'
                            paid_date = due_date + timedelta(days=random.randint(1, 5))
                            penalty = 150.00  # Partial default administrative fee
                else:
                    # Future installment
                    inst_status = 'PENDING'
                    paid_date = None
                    penalty = 0.00

            emi_entry = {
                'emi_id': global_emi_id,
                'loan_id': l_id,
                'installment_no': row['installment_no'],
                'due_date': due_date,
                'principal_component': p_comp,
                'interest_component': i_comp,
                'emi_amount': emi_amt,
                'balance_after': bal_after,
                'status': inst_status,
                'paid_date': paid_date,
                'penalty_amount': penalty
            }
            emi_schedules.append(emi_entry)

            if inst_status in ('PAID', 'PARTIALLY_PAID'):
                paid_or_partial_emis.append(emi_entry)

            global_emi_id += 1

    # --------------------------------------------------------------------------
    # 8. Generate Exactly 200 REPAYMENT Records
    # --------------------------------------------------------------------------
    print(f"Generating exactly 200 REPAYMENT records from {len(paid_or_partial_emis)} available paid installments...")
    
    # Priority: ensure all PARTIALLY_PAID installments get a repayment row
    partial_emis = [e for e in paid_or_partial_emis if e['status'] == 'PARTIALLY_PAID']
    fully_paid_emis = [e for e in paid_or_partial_emis if e['status'] == 'PAID']

    # Sample 200 EMIs deterministically
    needed_paid_count = 200 - len(partial_emis)
    if needed_paid_count <= len(fully_paid_emis):
        sampled_fully_paid = random.sample(fully_paid_emis, needed_paid_count)
        selected_emis = partial_emis + sampled_fully_paid
    else:
        # Fallback if fewer (unlikely with 80 loans)
        selected_emis = (partial_emis + fully_paid_emis)[:200]

    # Sort selected EMIs by paid_date for chronological realism
    selected_emis.sort(key=lambda x: (x['paid_date'] if x['paid_date'] else x['due_date'], x['emi_id']))

    repayments = []
    payment_modes = ['AUTO_DEBIT', 'UPI', 'NEFT', 'CHEQUE', 'CASH']
    mode_weights = [0.45, 0.25, 0.15, 0.10, 0.05]

    for rep_id, emi_ref in enumerate(selected_emis, start=1):
        mode = random.choices(payment_modes, weights=mode_weights, k=1)[0]
        p_date = emi_ref['paid_date'] if emi_ref['paid_date'] else emi_ref['due_date']
        
        # Payment amount: full EMI if PAID, 40-70% if PARTIALLY_PAID
        if emi_ref['status'] == 'PAID':
            amount_paid = emi_ref['emi_amount']
            remarks_txt = f"Full installment #{emi_ref['installment_no']} cleared successfully."
        else:
            amount_paid = round(emi_ref['emi_amount'] * random.uniform(0.40, 0.70), 2)
            remarks_txt = f"Partial payment received for installment #{emi_ref['installment_no']}; residual due."

        # Unique Transaction Reference depending on payment mode
        date_str = p_date.strftime('%Y%m%d')
        if mode == 'AUTO_DEBIT':
            tx_ref = f"NACH{date_str}{random.randint(100000, 999999)}{rep_id:04d}"
        elif mode == 'UPI':
            tx_ref = f"UPI{date_str}{random.randint(100000, 999999)}{rep_id:04d}"
        elif mode == 'NEFT':
            tx_ref = f"NEFT{date_str}{random.randint(100000, 999999)}{rep_id:04d}"
        elif mode == 'CHEQUE':
            tx_ref = f"CHQ{random.randint(100000, 999999)}"
        else:
            tx_ref = f"CSH{date_str}{random.randint(100000, 999999)}{rep_id:04d}"

        # Late fee logic
        late_fee = 0.00
        if p_date > emi_ref['due_date']:
            late_fee = random.choice([0.00, 250.00, 350.00, 500.00])

        repayments.append({
            'repayment_id': rep_id,
            'emi_id': emi_ref['emi_id'],
            'loan_id': emi_ref['loan_id'],
            'amount_paid': amount_paid,
            'payment_date': p_date,
            'payment_mode': mode,
            'transaction_ref': tx_ref,
            'late_fee': late_fee,
            'remarks': remarks_txt
        })

    # --------------------------------------------------------------------------
    # 9. Generate Exactly 30 DEFAULT_LOG Records for DEFAULTED Loans
    # --------------------------------------------------------------------------
    print("Generating exactly 30 DEFAULT_LOG entries for the 15 DEFAULTED loans...")
    defaulted_loans = [l for l in loans if l['status'] == 'DEFAULTED']
    default_logs = []
    log_id = 1

    # Each of the 15 defaulted loans gets exactly 2 recovery tracking logs
    # Stage 1: Demand Notice (Section 13(2))
    # Stage 2: Legal Summons, Asset Possession, Restructuring, Settlement, or Write-Off
    for def_loan in defaulted_loans:
        l_id = def_loan['loan_id']
        principal = def_loan['principal_amount']
        disb_date = def_loan['disbursement_date']
        
        # Initial default occurred 6-12 months after disbursement
        stage1_default_date = add_months(disb_date, random.randint(6, 10))
        outstanding1 = round(principal * random.uniform(0.70, 0.95), 2)
        months_overdue1 = random.choice([3, 4])  # 90-120 days overdue

        # Entry 1: Demand Notice
        default_logs.append({
            'default_id': log_id,
            'loan_id': l_id,
            'default_date': stage1_default_date,
            'outstanding_amount': outstanding1,
            'months_overdue': months_overdue1,
            'action_taken': 'NOTICE_SENT',
            'resolved': False,
            'resolution_date': None,
            'remarks': 'Demand recall notice served under Section 13(2) of SARFAESI Act; 60-day cure period given.'
        })
        log_id += 1

        # Entry 2: Escalated Action (60-90 days after Stage 1)
        stage2_default_date = stage1_default_date + timedelta(days=random.randint(65, 95))
        months_overdue2 = months_overdue1 + random.choice([2, 3, 4])
        outstanding2 = round(outstanding1 * 1.03, 2)  # Penal interest accrued

        # Distribute realistic bank resolution outcomes across the 15 loans
        if log_id <= 8:  # 4 loans: Legal Notice / DRT
            action = 'LEGAL_NOTICE_ISSUED'
            resolved = False
            res_date = None
            remarks_act = 'Legal recovery proceedings initiated in Debt Recovery Tribunal (DRT); summons issued.'
        elif log_id <= 16:  # 4 loans: Collateral Seizure
            action = 'ASSET_SEIZED'
            resolved = False
            res_date = None
            remarks_act = 'Physical possession of collateral vehicle/property obtained under SARFAESI Section 13(4).'
        elif log_id <= 22:  # 3 loans: Debt Restructuring
            action = 'RESTRUCTURED'
            resolved = True
            res_date = stage2_default_date + timedelta(days=15)
            remarks_act = 'Borrower restructuring plan approved: Tenure extended by 24 months with revised EMI.'
        elif log_id <= 26:  # 2 loans: OTS Settlement
            action = 'SETTLEMENT_OFFERED'
            resolved = True
            res_date = stage2_default_date + timedelta(days=30)
            remarks_act = 'One-Time Settlement (OTS) finalized at 80% book value; compromise amount realized.'
        else:  # 2 loans: Prudential Write-off
            action = 'WRITTEN_OFF'
            resolved = False
            res_date = None
            remarks_act = 'Account classified as Loss Asset; written off prudentially while recovery remains active.'

        default_logs.append({
            'default_id': log_id,
            'loan_id': l_id,
            'default_date': stage2_default_date,
            'outstanding_amount': outstanding2,
            'months_overdue': months_overdue2,
            'action_taken': action,
            'resolved': resolved,
            'resolution_date': res_date,
            'remarks': remarks_act
        })
        log_id += 1

    # --------------------------------------------------------------------------
    # 10. Generate 25 Historical LOAN_AUDIT Records
    # --------------------------------------------------------------------------
    print("Generating 25 historical LOAN_AUDIT records...")
    loan_audits = []
    audit_id = 1

    # Audit records representing status changes
    for l in loans[:25]:
        l_id = l['loan_id']
        st = l['status']
        c_time = l['created_at'] + timedelta(days=1, hours=random.randint(1, 12))

        if st in ('ACTIVE', 'CLOSED', 'DEFAULTED'):
            old_val = 'PENDING'
            new_val = 'APPROVED'
            field_name = 'status'
            user_by = 'LOAN_OFFICER_VERMA'
        elif st == 'APPROVED':
            old_val = 'PENDING'
            new_val = 'APPROVED'
            field_name = 'status'
            user_by = 'BRANCH_MGR_DESHMUKH'
        elif st == 'REJECTED':
            old_val = 'PENDING'
            new_val = 'REJECTED'
            field_name = 'status'
            user_by = 'UNDERWRITER_APPRAISAL'
        else:  # PENDING
            old_val = 'DRAFT'
            new_val = 'PENDING'
            field_name = 'status'
            user_by = 'CUSTOMER_PORTAL_API'

        loan_audits.append({
            'audit_id': audit_id,
            'loan_id': l_id,
            'field_changed': field_name,
            'old_value': old_val,
            'new_value': new_val,
            'changed_at': c_time,
            'changed_by': user_by
        })
        audit_id += 1

    # --------------------------------------------------------------------------
    # 11. Write seed.sql File
    # --------------------------------------------------------------------------
    print(f"Writing SQL seed script to: {out_file} ...")
    
    with open(out_file, 'w', encoding='utf-8') as f:
        # Header & Engine Directives
        f.write("-- ============================================================================\n")
        f.write("-- BANK LOAN MANAGEMENT SYSTEM: EMI PROCESSING, REPAYMENT & RISK ASSESSMENT\n")
        f.write("-- Database Seed File (MySQL 8.0 / InnoDB)\n")
        f.write("-- Auto-generated via scripts/generate_seed.py (Faker en_IN, Seed=42)\n")
        f.write("-- ============================================================================\n\n")

        f.write("USE bank_loan_db;\n\n")
        f.write("SET FOREIGN_KEY_CHECKS = 0;\n")
        f.write("START TRANSACTION;\n\n")

        f.write("-- ----------------------------------------------------------------------------\n")
        f.write("-- TRUNCATE existing tables for clean, deterministic data reload\n")
        f.write("-- ----------------------------------------------------------------------------\n")
        tables_to_truncate = [
            'LOAN_AUDIT',
            'DEFAULT_LOG',
            'REPAYMENT',
            'EMI_SCHEDULE',
            'LOAN',
            'GUARANTOR',
            'LOAN_PRODUCT',
            'APPLICANT'
        ]
        for tbl in tables_to_truncate:
            f.write(f"TRUNCATE TABLE `{tbl}`;\n")
        f.write("\nSET FOREIGN_KEY_CHECKS = 1;\n\n")

        # Table 1: APPLICANT
        f.write("-- ============================================================================\n")
        f.write(f"-- 1. APPLICANT (Total Records: {len(applicants)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `APPLICANT` (\n")
        f.write("    `applicant_id`, `name`, `email`, `phone`, `address`, `dob`,\n")
        f.write("    `pan_no`, `aadhaar_no`, `annual_income`, `credit_score`,\n")
        f.write("    `employment_type`, `employer_name`, `created_at`\n")
        f.write(") VALUES\n")
        for i, a in enumerate(applicants):
            comma = "," if i < len(applicants) - 1 else ";"
            f.write(f"({a['applicant_id']}, {sql_format(a['name'])}, {sql_format(a['email'])}, "
                    f"{sql_format(a['phone'])}, {sql_format(a['address'])}, {sql_format(a['dob'])}, "
                    f"{sql_format(a['pan_no'])}, {sql_format(a['aadhaar_no'])}, {sql_format(a['annual_income'])}, "
                    f"{a['credit_score']}, {sql_format(a['employment_type'])}, {sql_format(a['employer_name'])}, "
                    f"{sql_format(a['created_at'])}){comma}\n")
        f.write("\n")

        # Table 2: LOAN_PRODUCT
        f.write("-- ============================================================================\n")
        f.write(f"-- 2. LOAN_PRODUCT (Total Records: {len(loan_products_spec)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `LOAN_PRODUCT` (\n")
        f.write("    `product_id`, `name`, `product_type`, `interest_rate`, `min_amount`,\n")
        f.write("    `max_amount`, `min_tenure_months`, `max_tenure_months`,\n")
        f.write("    `processing_fee_pct`, `penalty_rate_pct`, `description`\n")
        f.write(") VALUES\n")
        for i, p in enumerate(loan_products_spec):
            comma = "," if i < len(loan_products_spec) - 1 else ";"
            f.write(f"({p['product_id']}, {sql_format(p['name'])}, {sql_format(p['product_type'])}, "
                    f"{sql_format(p['interest_rate'])}, {sql_format(p['min_amount'])}, {sql_format(p['max_amount'])}, "
                    f"{p['min_tenure_months']}, {p['max_tenure_months']}, {sql_format(p['processing_fee_pct'])}, "
                    f"{sql_format(p['penalty_rate_pct'])}, {sql_format(p['description'])}){comma}\n")
        f.write("\n")

        # Table 3: GUARANTOR
        f.write("-- ============================================================================\n")
        f.write(f"-- 3. GUARANTOR (Total Records: {len(guarantors)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `GUARANTOR` (\n")
        f.write("    `guarantor_id`, `name`, `phone`, `pan_no`, `relationship`,\n")
        f.write("    `annual_income`, `address`\n")
        f.write(") VALUES\n")
        for i, g in enumerate(guarantors):
            comma = "," if i < len(guarantors) - 1 else ";"
            f.write(f"({g['guarantor_id']}, {sql_format(g['name'])}, {sql_format(g['phone'])}, "
                    f"{sql_format(g['pan_no'])}, {sql_format(g['relationship'])}, "
                    f"{sql_format(g['annual_income'])}, {sql_format(g['address'])}){comma}\n")
        f.write("\n")

        # Table 4: LOAN
        f.write("-- ============================================================================\n")
        f.write(f"-- 4. LOAN (Total Records: {len(loans)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `LOAN` (\n")
        f.write("    `loan_id`, `applicant_id`, `product_id`, `guarantor_id`, `principal_amount`,\n")
        f.write("    `interest_rate`, `tenure_months`, `emi_amount`, `total_payable`,\n")
        f.write("    `disbursement_date`, `maturity_date`, `status`, `approved_by`,\n")
        f.write("    `remarks`, `created_at`\n")
        f.write(") VALUES\n")
        for i, l in enumerate(loans):
            comma = "," if i < len(loans) - 1 else ";"
            f.write(f"({l['loan_id']}, {l['applicant_id']}, {l['product_id']}, {sql_format(l['guarantor_id'])}, "
                    f"{sql_format(l['principal_amount'])}, {sql_format(l['interest_rate'])}, {l['tenure_months']}, "
                    f"{sql_format(l['emi_amount'])}, {sql_format(l['total_payable'])}, "
                    f"{sql_format(l['disbursement_date'])}, {sql_format(l['maturity_date'])}, "
                    f"{sql_format(l['status'])}, {sql_format(l['approved_by'])}, "
                    f"{sql_format(l['remarks'])}, {sql_format(l['created_at'])}){comma}\n")
        f.write("\n")

        # Table 5: EMI_SCHEDULE (Batch in chunks of 100 for high performance)
        f.write("-- ============================================================================\n")
        f.write(f"-- 5. EMI_SCHEDULE (Total Records: {len(emi_schedules)})\n")
        f.write("-- ============================================================================\n")
        chunk_size = 100
        for c_idx in range(0, len(emi_schedules), chunk_size):
            chunk = emi_schedules[c_idx:c_idx + chunk_size]
            f.write("INSERT INTO `EMI_SCHEDULE` (\n")
            f.write("    `emi_id`, `loan_id`, `installment_no`, `due_date`, `principal_component`,\n")
            f.write("    `interest_component`, `emi_amount`, `balance_after`, `status`,\n")
            f.write("    `paid_date`, `penalty_amount`\n")
            f.write(") VALUES\n")
            for i, e in enumerate(chunk):
                comma = "," if i < len(chunk) - 1 else ";"
                f.write(f"({e['emi_id']}, {e['loan_id']}, {e['installment_no']}, {sql_format(e['due_date'])}, "
                        f"{sql_format(e['principal_component'])}, {sql_format(e['interest_component'])}, "
                        f"{sql_format(e['emi_amount'])}, {sql_format(e['balance_after'])}, "
                        f"{sql_format(e['status'])}, {sql_format(e['paid_date'])}, "
                        f"{sql_format(e['penalty_amount'])}){comma}\n")
            f.write("\n")

        # Table 6: REPAYMENT
        f.write("-- ============================================================================\n")
        f.write(f"-- 6. REPAYMENT (Total Records: {len(repayments)})\n")
        f.write("-- ============================================================================\n")
        for c_idx in range(0, len(repayments), chunk_size):
            chunk = repayments[c_idx:c_idx + chunk_size]
            f.write("INSERT INTO `REPAYMENT` (\n")
            f.write("    `repayment_id`, `emi_id`, `loan_id`, `amount_paid`, `payment_date`,\n")
            f.write("    `payment_mode`, `transaction_ref`, `late_fee`, `remarks`\n")
            f.write(") VALUES\n")
            for i, r in enumerate(chunk):
                comma = "," if i < len(chunk) - 1 else ";"
                f.write(f"({r['repayment_id']}, {r['emi_id']}, {r['loan_id']}, {sql_format(r['amount_paid'])}, "
                        f"{sql_format(r['payment_date'])}, {sql_format(r['payment_mode'])}, "
                        f"{sql_format(r['transaction_ref'])}, {sql_format(r['late_fee'])}, "
                        f"{sql_format(r['remarks'])}){comma}\n")
            f.write("\n")

        # Table 7: DEFAULT_LOG
        f.write("-- ============================================================================\n")
        f.write(f"-- 7. DEFAULT_LOG (Total Records: {len(default_logs)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `DEFAULT_LOG` (\n")
        f.write("    `default_id`, `loan_id`, `default_date`, `outstanding_amount`,\n")
        f.write("    `months_overdue`, `action_taken`, `resolved`, `resolution_date`, `remarks`\n")
        f.write(") VALUES\n")
        for i, d in enumerate(default_logs):
            comma = "," if i < len(default_logs) - 1 else ";"
            f.write(f"({d['default_id']}, {d['loan_id']}, {sql_format(d['default_date'])}, "
                    f"{sql_format(d['outstanding_amount'])}, {d['months_overdue']}, "
                    f"{sql_format(d['action_taken'])}, {sql_format(d['resolved'])}, "
                    f"{sql_format(d['resolution_date'])}, {sql_format(d['remarks'])}){comma}\n")
        f.write("\n")

        # Table 8: LOAN_AUDIT
        f.write("-- ============================================================================\n")
        f.write(f"-- 8. LOAN_AUDIT (Total Records: {len(loan_audits)})\n")
        f.write("-- ============================================================================\n")
        f.write("INSERT INTO `LOAN_AUDIT` (\n")
        f.write("    `audit_id`, `loan_id`, `field_changed`, `old_value`, `new_value`,\n")
        f.write("    `changed_at`, `changed_by`\n")
        f.write(") VALUES\n")
        for i, a in enumerate(loan_audits):
            comma = "," if i < len(loan_audits) - 1 else ";"
            f.write(f"({a['audit_id']}, {a['loan_id']}, {sql_format(a['field_changed'])}, "
                    f"{sql_format(a['old_value'])}, {sql_format(a['new_value'])}, "
                    f"{sql_format(a['changed_at'])}, {sql_format(a['changed_by'])}){comma}\n")
        f.write("\n")

        f.write("COMMIT;\n")
        f.write("-- ============================================================================\n")
        f.write("-- End of Seed File\n")
        f.write("-- ============================================================================\n")

    # --------------------------------------------------------------------------
    # 12. Verification Summary Output
    # --------------------------------------------------------------------------
    print("\n" + "=" * 70)
    print("SUCCESS: Seed script generation completed!")
    print("=" * 70)
    print(f"File Output       : {out_file}")
    print(f"File Size         : {os.path.getsize(out_file) / 1024:.2f} KB")
    print(f"1. APPLICANT      : {len(applicants)} rows")
    print(f"2. LOAN_PRODUCT   : {len(loan_products_spec)} rows")
    print(f"3. GUARANTOR      : {len(guarantors)} rows")
    print(f"4. LOAN           : {len(loans)} rows")
    
    # Status breakdown
    status_counts = {}
    for l in loans:
        status_counts[l['status']] = status_counts.get(l['status'], 0) + 1
    for st, count in sorted(status_counts.items()):
        print(f"   - {st:<10}: {count} loans")

    print(f"5. EMI_SCHEDULE   : {len(emi_schedules)} installments (for 80 ACTIVE/CLOSED loans)")
    print(f"6. REPAYMENT      : {len(repayments)} payments (for PAID/PARTIALLY_PAID EMIs)")
    print(f"7. DEFAULT_LOG    : {len(default_logs)} recovery actions (for 15 DEFAULTED loans)")
    print(f"8. LOAN_AUDIT     : {len(loan_audits)} historical audit trail rows")
    print("=" * 70 + "\n")


if __name__ == '__main__':
    generate_seed()
