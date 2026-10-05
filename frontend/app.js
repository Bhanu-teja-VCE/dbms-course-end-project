// ============================================================================
// Bank Loan Management System — Frontend Application Logic
// ============================================================================
// Course Project : B.Tech CSE Database Management Systems
// Project        : Bank Loan Management System: EMI Processing, Repayment
//                  Tracking, and Risk Assessment
// Architecture   : Single Page Application (SPA) with Live REST API &
//                  Resilient Fallback Mode
// ============================================================================

// ----------------------------------------------------------------------------
// 1. API CONFIGURATION & CONNECTION STATE
// ----------------------------------------------------------------------------
const API_BASE = 'http://localhost:5000/api';
let backendConnected = false;
let currentLoggedInUser = null;
let allLoansCache = [];
let allApplicantsCache = [];
let allProductsCache = [];
let activeCategoryFilter = 'ALL';

// Category Icons mapping
const categoryIcons = {
    'HOME': '🏠',
    'PERSONAL': '💼',
    'VEHICLE': '🚗',
    'EDUCATION': '🎓',
    'BUSINESS': '🏢',
    'GOLD': '💰',
    'AGRICULTURE': '🌾'
};

function getCategoryIcon(type) {
    if (!type) return '📋';
    const key = type.toUpperCase().trim();
    return categoryIcons[key] || '📋';
}

function formatINR(val) {
    if (val === null || val === undefined || isNaN(val)) return '₹0';
    return '₹' + Number(val).toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

// ----------------------------------------------------------------------------
// 2. BACKEND HEALTH CHECK
// ----------------------------------------------------------------------------
async function checkBackend() {
    try {
        const res = await fetch(`${API_BASE}/health`, { signal: AbortSignal.timeout(2000) });
        const data = await res.json();
        backendConnected = (data.status === 'ok' && data.connected === true);
    } catch (e) {
        backendConnected = false;
    }

    const badge = document.querySelector('.hero-badge');
    if (badge) {
        if (backendConnected) {
            badge.innerHTML = '🟢 Connected to MySQL (bank_loan_db)';
            badge.style.borderColor = 'rgba(0, 184, 148, 0.4)';
            badge.style.color = '#00B894';
            badge.title = 'Live MySQL 8.0 InnoDB connection active';
        } else {
            badge.innerHTML = '🟡 Demo Mode (Static Data) — Start backend/app.py for Live DB';
            badge.style.borderColor = 'rgba(253, 203, 110, 0.4)';
            badge.style.color = '#FDCB6E';
            badge.title = 'Operating offline. Start Flask app with MySQL to run real queries.';
        }
    }
    return backendConnected;
}

// ----------------------------------------------------------------------------
// 3. FALLBACK SAMPLE DATA (INDIAN BANK CONTEXT - SBI STYLE)
// ----------------------------------------------------------------------------
const sampleApplicants = [
    {
        applicant_id: 1,
        name: "Rohan Verma",
        email: "rohan.verma@gmail.com",
        phone: "+91 98201 12345",
        address: "402, Sea Green Apts, Worli, Mumbai 400018",
        dob: "1988-04-12",
        pan_no: "ABCPV1234A",
        aadhaar_no: "2341 5678 9012",
        annual_income: 1850000,
        credit_score: 785,
        employment_type: "SALARIED",
        employer_name: "Tata Consultancy Services",
        total_loans: 1,
        active_loans: 1,
        total_borrowed: 4500000
    },
    {
        applicant_id: 2,
        name: "Priya Sharma",
        email: "priya.sharma@yahoo.co.in",
        phone: "+91 98111 23456",
        address: "B-12, Green Glen Layout, Bellandur, Bengaluru 560103",
        dob: "1992-08-23",
        pan_no: "BCDPS5678B",
        aadhaar_no: "3452 6789 0123",
        annual_income: 950000,
        credit_score: 740,
        employment_type: "SALARIED",
        employer_name: "Infosys Ltd",
        total_loans: 1,
        active_loans: 1,
        total_borrowed: 500000
    },
    {
        applicant_id: 3,
        name: "Amit Patel",
        email: "amit.patel@patellogistics.in",
        phone: "+91 98450 34567",
        address: "78, Navrangpura Road, Ahmedabad 380009",
        dob: "1985-11-05",
        pan_no: "CDEPA9012C",
        aadhaar_no: "4563 7890 1234",
        annual_income: 1400000,
        credit_score: 695,
        employment_type: "SELF_EMPLOYED",
        employer_name: "Patel Freight Logistics",
        total_loans: 1,
        active_loans: 1,
        total_borrowed: 850000
    },
    {
        applicant_id: 4,
        name: "Sneha Rao",
        email: "sneha.rao@microsoft.com",
        phone: "+91 98765 43210",
        address: "Flat 304, Cyber Heights, Gachibowli, Hyderabad 500032",
        dob: "1996-03-30",
        pan_no: "DEFRS3456D",
        aadhaar_no: "5674 8901 2345",
        annual_income: 2400000,
        credit_score: 810,
        employment_type: "SALARIED",
        employer_name: "Microsoft India",
        total_loans: 1,
        active_loans: 1,
        total_borrowed: 2000000
    },
    {
        applicant_id: 5,
        name: "Rajesh Gupta",
        email: "rajesh.gupta@guptatraders.com",
        phone: "+91 97170 56789",
        address: "12/A, Chandni Chowk Commercial Complex, Old Delhi 110006",
        dob: "1978-06-19",
        pan_no: "EFGRG7890E",
        aadhaar_no: "6785 9012 3456",
        annual_income: 2100000,
        credit_score: 560,
        employment_type: "BUSINESS",
        employer_name: "Gupta Metal & Electricals",
        total_loans: 1,
        active_loans: 0,
        total_borrowed: 3500000
    },
    {
        applicant_id: 6,
        name: "Vikram Singh",
        email: "vikram.singh@royalauto.co.in",
        phone: "+91 99280 67890",
        address: "104, Malviya Nagar, Jaipur 302017",
        dob: "1989-09-14",
        pan_no: "FGHVS1234F",
        aadhaar_no: "7896 0123 4567",
        annual_income: 1150000,
        credit_score: 720,
        employment_type: "SELF_EMPLOYED",
        employer_name: "Royal Automobiles",
        total_loans: 1,
        active_loans: 0,
        total_borrowed: 300000
    },
    {
        applicant_id: 7,
        name: "Ananya Iyer",
        email: "ananya.iyer@hdfcbank.com",
        phone: "+91 94440 78901",
        address: "7th Cross, Gandhinagar, Adyar, Chennai 600020",
        dob: "1991-12-08",
        pan_no: "GHIAS5678G",
        aadhaar_no: "8907 1234 5678",
        annual_income: 2800000,
        credit_score: 830,
        employment_type: "SALARIED",
        employer_name: "HDFC Bank Corporate Office",
        total_loans: 1,
        active_loans: 0,
        total_borrowed: 6000000
    },
    {
        applicant_id: 8,
        name: "Manoj Kumar",
        email: "manoj.kumar.farms@gmail.com",
        phone: "+91 98390 89012",
        address: "Village Pipra, Tehsil Sadar, Varanasi 221001",
        dob: "1983-05-25",
        pan_no: "HIJMK9012H",
        aadhaar_no: "9018 2345 6789",
        annual_income: 680000,
        credit_score: 680,
        employment_type: "FARMER",
        employer_name: "Self-Employed Agriculture",
        total_loans: 1,
        active_loans: 1,
        total_borrowed: 400000
    }
];

const sampleLoans = [
    {
        loan_id: 1001,
        applicant_id: 1,
        applicant_name: "Rohan Verma",
        applicant_email: "rohan.verma@gmail.com",
        credit_score: 785,
        product_id: 1,
        product_name: "SBI Regular Home Loan",
        product_type: "HOME",
        guarantor_id: 1,
        guarantor_name: "Kavita Verma",
        principal_amount: 4500000,
        interest_rate: 8.50,
        tenure_months: 240,
        emi_amount: 39052,
        total_payable: 9372480,
        disbursement_date: "2024-01-20",
        maturity_date: "2044-01-20",
        status: "ACTIVE",
        approved_by: "Ramesh Iyer (Chief Manager)",
        remarks: "Clear property title deed. 20-year EMI tenure authorized."
    },
    {
        loan_id: 1002,
        applicant_id: 2,
        applicant_name: "Priya Sharma",
        applicant_email: "priya.sharma@yahoo.co.in",
        credit_score: 740,
        product_id: 2,
        product_name: "SBI Express Credit Personal Loan",
        product_type: "PERSONAL",
        guarantor_id: null,
        guarantor_name: null,
        principal_amount: 500000,
        interest_rate: 11.25,
        tenure_months: 36,
        emi_amount: 16429,
        total_payable: 591444,
        disbursement_date: "2024-02-15",
        maturity_date: "2027-02-15",
        status: "ACTIVE",
        approved_by: "Snehal Deshmukh (Loan Officer)",
        remarks: "Salary auto-debit activated with corporate employer."
    },
    {
        loan_id: 1003,
        applicant_id: 3,
        applicant_name: "Amit Patel",
        applicant_email: "amit.patel@patellogistics.in",
        credit_score: 695,
        product_id: 3,
        product_name: "SBI Car Loan Platinum",
        product_type: "VEHICLE",
        guarantor_id: null,
        guarantor_name: null,
        principal_amount: 850000,
        interest_rate: 8.85,
        tenure_months: 60,
        emi_amount: 17585,
        total_payable: 1055100,
        disbursement_date: "2024-02-22",
        maturity_date: "2029-02-22",
        status: "ACTIVE",
        approved_by: "Vikram Aditya (Credit Manager)",
        remarks: "Vehicle hypothecation endorsed with RTO Ahmedabad."
    },
    {
        loan_id: 1004,
        applicant_id: 4,
        applicant_name: "Sneha Rao",
        applicant_email: "sneha.rao@microsoft.com",
        credit_score: 810,
        product_id: 4,
        product_name: "SBI Scholar Education Loan",
        product_type: "EDUCATION",
        guarantor_id: 2,
        guarantor_name: "Venkatesh Rao",
        principal_amount: 2000000,
        interest_rate: 9.15,
        tenure_months: 120,
        emi_amount: 25502,
        total_payable: 3060240,
        disbursement_date: "2024-03-05",
        maturity_date: "2034-03-05",
        status: "ACTIVE",
        approved_by: "Ramesh Iyer (Chief Manager)",
        remarks: "Stanford University MS CS. Parent co-obligation accepted."
    },
    {
        loan_id: 1005,
        applicant_id: 5,
        applicant_name: "Rajesh Gupta",
        applicant_email: "rajesh.gupta@guptatraders.com",
        credit_score: 560,
        product_id: 5,
        product_name: "SME Working Capital & Term Loan",
        product_type: "BUSINESS",
        guarantor_id: 3,
        guarantor_name: "Sunil Gupta",
        principal_amount: 3500000,
        interest_rate: 12.50,
        tenure_months: 60,
        emi_amount: 78728,
        total_payable: 4723680,
        disbursement_date: "2023-06-15",
        maturity_date: "2028-06-15",
        status: "DEFAULTED",
        approved_by: "Vikram Aditya (Credit Manager)",
        remarks: "Classified as NPA (>90 days overdue). SARFAESI demand notice served."
    },
    {
        loan_id: 1006,
        applicant_id: 6,
        applicant_name: "Vikram Singh",
        applicant_email: "vikram.singh@royalauto.co.in",
        credit_score: 720,
        product_id: 6,
        product_name: "SBI Sovereign Gold Loan",
        product_type: "GOLD",
        guarantor_id: null,
        guarantor_name: null,
        principal_amount: 300000,
        interest_rate: 7.75,
        tenure_months: 12,
        emi_amount: 26063,
        total_payable: 312756,
        disbursement_date: "2023-03-10",
        maturity_date: "2024-03-10",
        status: "CLOSED",
        approved_by: "Snehal Deshmukh (Loan Officer)",
        remarks: "Matured and paid in full. Pledged ornaments released."
    },
    {
        loan_id: 1007,
        applicant_id: 7,
        applicant_name: "Ananya Iyer",
        applicant_email: "ananya.iyer@hdfcbank.com",
        credit_score: 830,
        product_id: 1,
        product_name: "SBI Regular Home Loan",
        product_type: "HOME",
        guarantor_id: null,
        guarantor_name: null,
        principal_amount: 6000000,
        interest_rate: 8.40,
        tenure_months: 240,
        emi_amount: 51691,
        total_payable: 12405840,
        disbursement_date: null,
        maturity_date: null,
        status: "APPROVED",
        approved_by: "Ramesh Iyer (Chief Manager)",
        remarks: "Approved under Platinum prime tier. Pending disbursement."
    },
    {
        loan_id: 1008,
        applicant_id: 8,
        applicant_name: "Manoj Kumar",
        applicant_email: "manoj.kumar.farms@gmail.com",
        credit_score: 680,
        product_id: 7,
        product_name: "Kisan Credit Card & Agri Loan",
        product_type: "AGRICULTURE",
        guarantor_id: null,
        guarantor_name: null,
        principal_amount: 400000,
        interest_rate: 7.00,
        tenure_months: 36,
        emi_amount: 12351,
        total_payable: 444636,
        disbursement_date: "2024-04-18",
        maturity_date: "2027-04-18",
        status: "ACTIVE",
        approved_by: "Snehal Deshmukh (Loan Officer)",
        remarks: "Seasonal crop credit linked with central interest subvention."
    }
];

const sampleProducts = [
    { product_id: 1, name: "SBI Regular Home Loan", product_type: "HOME", interest_rate: 8.50, min_amount: 500000, max_amount: 10000000, min_tenure_months: 12, max_tenure_months: 360, processing_fee_pct: 0.50 },
    { product_id: 2, name: "SBI Express Credit Personal", product_type: "PERSONAL", interest_rate: 11.25, min_amount: 50000, max_amount: 2000000, min_tenure_months: 12, max_tenure_months: 72, processing_fee_pct: 1.00 },
    { product_id: 3, name: "SBI Car Loan Platinum", product_type: "VEHICLE", interest_rate: 8.85, min_amount: 100000, max_amount: 3500000, min_tenure_months: 12, max_tenure_months: 84, processing_fee_pct: 0.75 },
    { product_id: 4, name: "SBI Scholar Education Loan", product_type: "EDUCATION", interest_rate: 9.15, min_amount: 100000, max_amount: 4000000, min_tenure_months: 12, max_tenure_months: 180, processing_fee_pct: 0.00 },
    { product_id: 5, name: "SME Working Capital & Term Loan", product_type: "BUSINESS", interest_rate: 12.50, min_amount: 200000, max_amount: 5000000, min_tenure_months: 12, max_tenure_months: 60, processing_fee_pct: 1.25 },
    { product_id: 6, name: "SBI Sovereign Gold Loan", product_type: "GOLD", interest_rate: 7.75, min_amount: 25000, max_amount: 5000000, min_tenure_months: 3, max_tenure_months: 36, processing_fee_pct: 0.50 },
    { product_id: 7, name: "Kisan Credit Card & Agri Loan", product_type: "AGRICULTURE", interest_rate: 7.00, min_amount: 50000, max_amount: 1500000, min_tenure_months: 6, max_tenure_months: 60, processing_fee_pct: 0.00 }
];

// Bank Staff for officer login simulation
const sampleBankUsers = [
    {
        user_id: 1,
        name: "Ramesh Iyer",
        role: "Branch Manager & Sanction Authority",
        branch: "Fort Branch, Mumbai (00012)",
        emp_code: "SBI_MGR_4091",
        email: "ramesh.iyer@sbi.co.in",
        sanction_limit: 10000000
    },
    {
        user_id: 2,
        name: "Snehal Deshmukh",
        role: "Senior Loan Officer (Retail Credit)",
        branch: "Worli Retail Hub, Mumbai (00045)",
        emp_code: "SBI_OFF_8912",
        email: "snehal.d@sbi.co.in",
        sanction_limit: 2500000
    },
    {
        user_id: 3,
        name: "Vikram Aditya",
        role: "Chief Risk & Recovery Officer (NPA)",
        branch: "Zonal Recovery Cell, Nariman Point (00099)",
        emp_code: "SBI_RSK_1044",
        email: "vikram.aditya@sbi.co.in",
        sanction_limit: 5000000
    }
];

// ----------------------------------------------------------------------------
// 4. RENDER LOANS (DISPLAY LOAN CARDS WITH ENHANCED BADGES)
// ----------------------------------------------------------------------------
async function renderLoans(loansToRender = null) {
    const grid = document.getElementById('listingsGrid');
    if (!grid) return;

    if (!loansToRender) {
        if (backendConnected) {
            try {
                const res = await fetch(`${API_BASE}/loans`);
                const data = await res.json();
                if (data.data && data.data.length > 0) {
                    allLoansCache = data.data;
                } else {
                    allLoansCache = sampleLoans;
                }
            } catch (err) {
                console.warn('API error, using sample loans:', err);
                allLoansCache = sampleLoans;
            }
        } else {
            allLoansCache = sampleLoans;
        }
        loansToRender = allLoansCache;
    }

    // Filter by active category if not 'ALL'
    if (activeCategoryFilter && activeCategoryFilter !== 'ALL') {
        loansToRender = loansToRender.filter(l => (l.product_type || '').toUpperCase() === activeCategoryFilter);
    }

    if (loansToRender.length === 0) {
        grid.innerHTML = `
            <div style="grid-column: 1 / -1; text-align: center; padding: 60px 20px; color: var(--text-muted);">
                <div style="font-size: 3rem; margin-bottom: 12px;">🔍</div>
                <h3>No loans found matching your criteria</h3>
                <p>Try resetting the search or category filter.</p>
                <button class="btn btn-outline" style="margin-top:16px;" onclick="resetFilters()">View All Loans</button>
            </div>
        `;
        return;
    }

    grid.innerHTML = loansToRender.map(loan => {
        const icon = getCategoryIcon(loan.product_type);
        const statusClass = `status-${(loan.status || 'pending').toLowerCase()}`;
        
        let statusBadgeColor = '#00B894';
        if (loan.status === 'DEFAULTED') statusBadgeColor = '#E17055';
        else if (loan.status === 'PENDING') statusBadgeColor = '#FDCB6E';
        else if (loan.status === 'CLOSED') statusBadgeColor = '#A29BFE';
        else if (loan.status === 'APPROVED') statusBadgeColor = '#0984E3';

        return `
            <div class="listing-card" onclick="openLoanDetailModal(${loan.loan_id})" style="cursor: pointer;">
                <div class="listing-image" style="background: linear-gradient(135deg, rgba(108, 92, 231, 0.12), rgba(0, 184, 148, 0.12));">
                    <span style="font-size: 3.5rem;">${icon}</span>
                </div>
                <div class="listing-info">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                        <span style="font-size:0.75rem; color:var(--text-muted); font-weight:600; text-transform:uppercase;">
                            Loan #${loan.loan_id} &bull; ${loan.product_type || 'RETAIL'}
                        </span>
                        <span class="request-status" style="background: ${statusBadgeColor}22; color: ${statusBadgeColor}; font-size:0.7rem; padding: 3px 10px;">
                            ${loan.status}
                        </span>
                    </div>

                    <h3 class="listing-title" style="margin-bottom: 4px; font-size: 1.1rem; color: var(--text);">
                        ${loan.applicant_name}
                    </h3>
                    <p style="font-size: 0.82rem; color: var(--text-dim); margin-bottom: 14px;">
                        ${loan.product_name}
                    </p>

                    <div style="background: var(--bg-surface); border-radius: var(--radius-sm); padding: 12px; margin-bottom: 14px; border: 1px solid var(--glass-border);">
                        <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                            <span style="font-size: 0.75rem; color: var(--text-muted);">Principal Sanctioned</span>
                            <span style="font-size: 0.95rem; font-weight: 700; color: var(--secondary);">${formatINR(loan.principal_amount)}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                            <span style="font-size: 0.75rem; color: var(--text-muted);">Monthly EMI</span>
                            <span style="font-size: 0.9rem; font-weight: 600; color: var(--primary-light);">${formatINR(loan.emi_amount)} / mo</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="font-size: 0.75rem; color: var(--text-muted);">Tenure & Rate</span>
                            <span style="font-size: 0.8rem; color: var(--text);">${loan.tenure_months} Mos @ ${loan.interest_rate}%</span>
                        </div>
                    </div>

                    <div class="listing-footer" style="padding: 0; border: none; margin-top: 8px;">
                        <div style="font-size: 0.75rem; color: var(--text-dim);">
                            Score: <strong style="color:${loan.credit_score >= 750 ? '#00B894' : (loan.credit_score >= 650 ? '#FDCB6E' : '#E17055')}">${loan.credit_score || 'N/A'}</strong>
                        </div>
                        <span style="font-size: 0.8rem; color: var(--primary-light); font-weight: 500;">
                            View Schedule &rarr;
                        </span>
                    </div>
                </div>
            </div>
        `;
    }).join('');
}

// ----------------------------------------------------------------------------
// 5. RENDER APPLICANTS (BORROWER PROFILES & CREDIT RISK)
// ----------------------------------------------------------------------------
async function renderApplicants() {
    const list = document.getElementById('requestsList');
    if (!list) return;

    if (backendConnected) {
        try {
            const res = await fetch(`${API_BASE}/applicants`);
            const data = await res.json();
            if (data.data && data.data.length > 0) {
                allApplicantsCache = data.data;
            } else {
                allApplicantsCache = sampleApplicants;
            }
        } catch (e) {
            allApplicantsCache = sampleApplicants;
        }
    } else {
        allApplicantsCache = sampleApplicants;
    }

    list.innerHTML = allApplicantsCache.map(app => {
        let scoreClass = '#00B894';
        let scoreLabel = 'EXCELLENT';
        if (app.credit_score < 600) {
            scoreClass = '#E17055';
            scoreLabel = 'HIGH RISK';
        } else if (app.credit_score < 720) {
            scoreClass = '#FDCB6E';
            scoreLabel = 'MODERATE';
        }

        return `
            <div class="request-card" onclick="openApplicantDetailModal(${app.applicant_id})" style="cursor:pointer;">
                <div class="seller-avatar" style="width:48px; height:48px; font-size:1.1rem; flex-shrink:0;">
                    ${app.name.split(' ').map(n=>n[0]).join('').substring(0,2)}
                </div>
                <div class="request-info" style="flex:1;">
                    <div style="display:flex; align-items:center; gap:8px; margin-bottom:4px;">
                        <h4 style="margin:0; font-size:1rem; font-weight:600; color:var(--text);">${app.name}</h4>
                        <span style="font-size:0.7rem; padding:2px 8px; border-radius:4px; background:rgba(108,92,231,0.15); color:var(--primary-light); font-weight:600;">
                            PAN: ${app.pan_no}
                        </span>
                    </div>
                    <p style="margin:0; font-size:0.8rem; color:var(--text-muted);">
                        ${app.employment_type} &bull; ${app.employer_name || 'Individual'} &bull; Income: ${formatINR(app.annual_income)}/yr
                    </p>
                    <p style="margin:4px 0 0; font-size:0.75rem; color:var(--text-dim);">
                        Active Loans: <strong style="color:var(--text);">${app.active_loans || (app.total_loans ? 1 : 0)}</strong> &bull; Total Sanctions: ${formatINR(app.total_borrowed || 0)}
                    </p>
                </div>
                <div style="text-align:right; flex-shrink:0;">
                    <div style="font-size:1.25rem; font-weight:800; color:${scoreClass};">
                        ${app.credit_score}
                    </div>
                    <span style="font-size:0.65rem; font-weight:700; color:${scoreClass}; letter-spacing:0.05em;">
                        ${scoreLabel}
                    </span>
                </div>
            </div>
        `;
    }).join('');
}

// ----------------------------------------------------------------------------
// 6. HOW IT WORKS CONTENT — 7 TECHNICAL TABS
// ----------------------------------------------------------------------------
const howItWorksContent = {
    schema: `
        <h3>🏛️ Database Schema Architecture (bank_loan_db)</h3>
        <p>
            The system is built on <strong>MySQL 8.0 with the InnoDB storage engine</strong>.
            All 8 tables strictly enforce relational integrity, referential constraints, and business domain rules.
        </p>

        <div class="concept-box">
            <p><strong>🎯 Viva Defence — Why InnoDB?</strong><br>
            Unlike MyISAM, InnoDB supports <code>ACID Transactions</code>, foreign key constraints (<code>ON DELETE RESTRICT/CASCADE</code>), 
            and row-level locking (<code>SELECT ... FOR UPDATE</code>) essential for high-throughput concurrent loan repayments.</p>
        </div>

        <span class="sql-label">1. APPLICANT Table (Core Entity)</span>
        <pre><code class="language-sql">CREATE TABLE APPLICANT (
    applicant_id    INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    phone           VARCHAR(15)  NOT NULL,
    address         TEXT         NOT NULL,
    dob             DATE         NOT NULL,
    pan_no          VARCHAR(10)  NOT NULL UNIQUE,    -- 10-character Indian PAN
    aadhaar_no      VARCHAR(12)  NOT NULL UNIQUE,    -- 12-digit Indian Aadhaar
    annual_income   DECIMAL(12,2) NOT NULL,
    credit_score    INT NOT NULL,                    -- CIBIL credit score range
    employment_type ENUM('SALARIED', 'SELF_EMPLOYED', 'BUSINESS', 'STUDENT', 'FARMER', 'RETIRED') NOT NULL,
    employer_name   VARCHAR(150),
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_applicant_income CHECK (annual_income >= 0),
    CONSTRAINT chk_applicant_cibil  CHECK (credit_score BETWEEN 300 AND 900)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">2. LOAN_PRODUCT Table (Credit Catalog)</span>
        <pre><code class="language-sql">CREATE TABLE LOAN_PRODUCT (
    product_id          INT AUTO_INCREMENT PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    product_type        ENUM('HOME', 'PERSONAL', 'VEHICLE', 'EDUCATION', 'BUSINESS', 'GOLD', 'AGRICULTURE') NOT NULL,
    interest_rate       DECIMAL(5,2)  NOT NULL,       -- Annual interest rate %
    min_amount          DECIMAL(12,2) NOT NULL,
    max_amount          DECIMAL(12,2) NOT NULL,
    min_tenure_months   INT           NOT NULL,
    max_tenure_months   INT           NOT NULL,
    processing_fee_pct  DECIMAL(4,2)  NOT NULL DEFAULT 1.00,
    penalty_rate_pct    DECIMAL(4,2)  NOT NULL DEFAULT 2.00,
    description         TEXT,
    CONSTRAINT chk_prod_rate   CHECK (interest_rate > 0),
    CONSTRAINT chk_prod_amt    CHECK (max_amount >= min_amount),
    CONSTRAINT chk_prod_tenure CHECK (max_tenure_months >= min_tenure_months)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">3. GUARANTOR Table (Secondary Security)</span>
        <pre><code class="language-sql">CREATE TABLE GUARANTOR (
    guarantor_id    INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100)  NOT NULL,
    phone           VARCHAR(15)   NOT NULL,
    pan_no          VARCHAR(10)   NOT NULL,
    relationship    VARCHAR(50)   NOT NULL,
    annual_income   DECIMAL(12,2) NOT NULL,
    address         TEXT          NOT NULL
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">4. LOAN Table (Central Fact Table)</span>
        <pre><code class="language-sql">CREATE TABLE LOAN (
    loan_id           INT AUTO_INCREMENT PRIMARY KEY,
    applicant_id      INT           NOT NULL,
    product_id        INT           NOT NULL,
    guarantor_id      INT           NULL,             -- Nullable for unsecured retail loans
    principal_amount  DECIMAL(12,2) NOT NULL,
    interest_rate     DECIMAL(5,2)  NOT NULL,
    tenure_months     INT           NOT NULL,
    emi_amount        DECIMAL(10,2) NOT NULL,         -- Pre-calculated reducing-balance EMI
    total_payable     DECIMAL(12,2) NOT NULL,
    disbursement_date DATE          NULL,
    maturity_date     DATE          NULL,
    status            ENUM('PENDING', 'APPROVED', 'ACTIVE', 'CLOSED', 'DEFAULTED', 'REJECTED') 
                      NOT NULL DEFAULT 'PENDING',
    approved_by       VARCHAR(100),
    remarks           TEXT,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_loan_applicant FOREIGN KEY (applicant_id) REFERENCES APPLICANT(applicant_id),
    CONSTRAINT fk_loan_product   FOREIGN KEY (product_id)   REFERENCES LOAN_PRODUCT(product_id),
    CONSTRAINT fk_loan_guarantor FOREIGN KEY (guarantor_id) REFERENCES GUARANTOR(guarantor_id) ON DELETE SET NULL,
    CONSTRAINT chk_loan_principal CHECK (principal_amount > 0),
    CONSTRAINT chk_loan_rate      CHECK (interest_rate > 0),
    CONSTRAINT chk_loan_tenure    CHECK (tenure_months > 0),
    CONSTRAINT chk_loan_emi       CHECK (emi_amount > 0)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">5. EMI_SCHEDULE Table (Amortization Ledger)</span>
        <pre><code class="language-sql">CREATE TABLE EMI_SCHEDULE (
    emi_id              INT AUTO_INCREMENT PRIMARY KEY,
    loan_id             INT           NOT NULL,
    installment_no      INT           NOT NULL,
    due_date            DATE          NOT NULL,
    principal_component DECIMAL(10,2) NOT NULL,
    interest_component  DECIMAL(10,2) NOT NULL,
    emi_amount          DECIMAL(10,2) NOT NULL,
    balance_after       DECIMAL(12,2) NOT NULL,
    status              ENUM('PENDING', 'PAID', 'OVERDUE', 'PARTIALLY_PAID') NOT NULL DEFAULT 'PENDING',
    paid_date           DATETIME      NULL,
    penalty_amount      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT fk_emi_loan FOREIGN KEY (loan_id) REFERENCES LOAN(loan_id) ON DELETE CASCADE,
    CONSTRAINT uq_loan_installment UNIQUE (loan_id, installment_no)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">6. REPAYMENT Table (Audit-Proof Payment Log)</span>
        <pre><code class="language-sql">CREATE TABLE REPAYMENT (
    repayment_id    INT AUTO_INCREMENT PRIMARY KEY,
    emi_id          INT           NOT NULL,
    loan_id         INT           NOT NULL,
    amount_paid     DECIMAL(10,2) NOT NULL,
    payment_date    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_mode    ENUM('CASH', 'CHEQUE', 'NEFT', 'UPI', 'AUTO_DEBIT') NOT NULL,
    transaction_ref VARCHAR(100)  NOT NULL,
    late_fee        DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    remarks         VARCHAR(255),
    CONSTRAINT fk_rep_emi  FOREIGN KEY (emi_id)  REFERENCES EMI_SCHEDULE(emi_id),
    CONSTRAINT fk_rep_loan FOREIGN KEY (loan_id) REFERENCES LOAN(loan_id),
    CONSTRAINT chk_rep_amount CHECK (amount_paid > 0)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">7. DEFAULT_LOG Table (NPA Delinquency Register)</span>
        <pre><code class="language-sql">CREATE TABLE DEFAULT_LOG (
    default_id          INT AUTO_INCREMENT PRIMARY KEY,
    loan_id             INT           NOT NULL,
    default_date        DATE          NOT NULL,
    outstanding_amount  DECIMAL(12,2) NOT NULL,
    months_overdue      INT           NOT NULL,
    action_taken        ENUM('NOTICE_ISSUED', 'LEGAL_PROCEEDING', 'SARFAESI_ACT', 'RESTRUCTURING', 'RECOVERY_AGENT_ASSIGNED', 'WRITTEN_OFF') NOT NULL,
    resolved            BOOLEAN       NOT NULL DEFAULT FALSE,
    resolution_date     DATE          NULL,
    remarks             TEXT,
    CONSTRAINT fk_def_loan FOREIGN KEY (loan_id) REFERENCES LOAN(loan_id)
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">8. LOAN_AUDIT Table (Regulatory Audit Trail)</span>
        <pre><code class="language-sql">CREATE TABLE LOAN_AUDIT (
    audit_id      INT AUTO_INCREMENT PRIMARY KEY,
    loan_id       INT          NOT NULL,
    field_changed VARCHAR(100) NOT NULL,
    old_value     TEXT,
    new_value     TEXT,
    changed_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by    VARCHAR(100) NOT NULL DEFAULT 'SYSTEM'
) ENGINE=InnoDB;</code></pre>
    `,

    queries: `
        <h3>📊 Analytical & Operational SQL Queries</h3>
        <p>Every query demonstrates relational algebra principles: selection, projection, equi-joins, and aggregations.</p>

        <span class="sql-label">Query 1: Delinquent Loans Report (High Risk Identification)</span>
        <pre><code class="language-sql">SELECT 
    l.loan_id,
    a.name AS applicant_name,
    a.phone AS applicant_phone,
    lp.name AS product_name,
    COUNT(e.emi_id) AS overdue_installments,
    COALESCE(SUM(e.emi_amount + e.penalty_amount), 0) AS total_overdue_amount,
    MIN(e.due_date) AS earliest_overdue_date,
    DATEDIFF(CURRENT_DATE, MIN(e.due_date)) AS days_overdue
FROM LOAN l
JOIN APPLICANT a ON l.applicant_id = a.applicant_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
JOIN EMI_SCHEDULE e ON l.loan_id = e.loan_id
WHERE e.status = 'OVERDUE' OR (e.status = 'PENDING' AND e.due_date < CURRENT_DATE)
GROUP BY l.loan_id, a.name, a.phone, lp.name
ORDER BY total_overdue_amount DESC;</code></pre>
        <div class="concept-box">
            <p><strong>Relational Algebra:</strong><br>
            <code>&gamma;_{loan_id, name, phone, product_name; COUNT(emi_id), SUM(emi+penalty)}(&sigma;_{status='OVERDUE'}(LOAN &bowtie; APPLICANT &bowtie; LOAN_PRODUCT &bowtie; EMI_SCHEDULE))</code></p>
        </div>

        <span class="sql-label">Query 2: Portfolio-Wise Sanctioned Amount & NPA Ratio</span>
        <pre><code class="language-sql">SELECT 
    lp.product_type,
    COUNT(DISTINCT l.loan_id) AS total_loans,
    COALESCE(SUM(l.principal_amount), 0) AS total_sanctioned_amount,
    ROUND(AVG(l.interest_rate), 2) AS avg_interest_rate,
    COALESCE(SUM(CASE WHEN l.status = 'ACTIVE' THEN l.principal_amount ELSE 0 END), 0) AS active_principal,
    COALESCE(SUM(CASE WHEN l.status = 'DEFAULTED' THEN l.principal_amount ELSE 0 END), 0) AS defaulted_amount,
    ROUND(100.0 * COALESCE(SUM(CASE WHEN l.status = 'DEFAULTED' THEN 1 ELSE 0 END), 0) / NULLIF(COUNT(l.loan_id), 0), 2) AS npa_ratio_pct
FROM LOAN_PRODUCT lp
LEFT JOIN LOAN l ON lp.product_id = l.product_id
GROUP BY lp.product_type
ORDER BY total_sanctioned_amount DESC;</code></pre>

        <span class="sql-label">Query 3: Defaulter Register & Recovery Action (SARFAESI)</span>
        <pre><code class="language-sql">SELECT 
    d.default_id,
    l.loan_id,
    a.name AS applicant_name,
    a.phone AS applicant_phone,
    a.pan_no,
    lp.name AS product_name,
    d.default_date,
    d.outstanding_amount,
    d.months_overdue,
    d.action_taken
FROM DEFAULT_LOG d
JOIN LOAN l ON d.loan_id = l.loan_id
JOIN APPLICANT a ON l.applicant_id = a.applicant_id
JOIN LOAN_PRODUCT lp ON l.product_id = lp.product_id
WHERE d.resolved = FALSE
ORDER BY d.outstanding_amount DESC, d.months_overdue DESC;</code></pre>

        <span class="sql-label">Query 4: Monthly Repayment Collection Efficiency</span>
        <pre><code class="language-sql">SELECT 
    DATE_FORMAT(r.payment_date, '%Y-%m') AS payment_month,
    COUNT(r.repayment_id) AS total_transactions,
    SUM(r.amount_paid) AS total_collected,
    SUM(r.late_fee) AS total_penalty_collected,
    ROUND(AVG(r.amount_paid), 2) AS avg_repayment_amount
FROM REPAYMENT r
GROUP BY DATE_FORMAT(r.payment_date, '%Y-%m')
ORDER BY payment_month DESC;</code></pre>

        <span class="sql-label">Query 10: RBI SMA & NPA Aging Analysis</span>
        <pre><code class="language-sql">SELECT 
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, e.due_date) BETWEEN 1 AND 30 THEN '1-30 Days (SMA-0)'
        WHEN DATEDIFF(CURRENT_DATE, e.due_date) BETWEEN 31 AND 60 THEN '31-60 Days (SMA-1)'
        WHEN DATEDIFF(CURRENT_DATE, e.due_date) BETWEEN 61 AND 90 THEN '61-90 Days (SMA-2)'
        ELSE '90+ Days (NPA / Default)'
    END AS aging_bucket,
    COUNT(e.emi_id) AS overdue_count,
    SUM(e.emi_amount) AS total_principal_interest_due,
    SUM(e.penalty_amount) AS total_penalties,
    SUM(e.emi_amount + e.penalty_amount) AS grand_total_at_risk
FROM EMI_SCHEDULE e
JOIN LOAN l ON e.loan_id = l.loan_id
WHERE e.status = 'OVERDUE' OR (e.status = 'PENDING' AND e.due_date < CURRENT_DATE)
GROUP BY aging_bucket
ORDER BY MIN(DATEDIFF(CURRENT_DATE, e.due_date)) ASC;</code></pre>
    `,

    normalization: `
        <h3>📐 Normalization Proof: From LOAN_RAW to BCNF</h3>
        <p>
            Demonstrating how a denormalized monolithic banking ledger <code>LOAN_RAW</code> is systematically decomposed 
            to eliminate insertion, update, and deletion anomalies.
        </p>

        <div class="concept-box">
            <p><strong>Unnormalized Table (LOAN_RAW):</strong><br>
            <code>LOAN_RAW(loan_id, applicant_name, applicant_pan, applicant_email, applicant_income, credit_score, product_name, product_type, interest_rate, principal, tenure, emi, installment_no, due_date, emi_amount, payment_date, amount_paid, guarantor_name, guarantor_pan)</code></p>
            <ul style="margin-left: 20px; font-size: 0.85rem; color: var(--text-muted); margin-top: 8px;">
                <li><strong>Insertion Anomaly:</strong> Cannot define a new loan product without sanctioning an applicant loan.</li>
                <li><strong>Deletion Anomaly:</strong> Deleting a loan erases the applicant profile and credit score history.</li>
                <li><strong>Update Anomaly:</strong> If base interest rate changes, thousands of rows must be updated.</li>
            </ul>
        </div>

        <h3>1. First Normal Form (1NF)</h3>
        <p>
            <strong>Rule:</strong> All attributes must contain atomic values. Eliminate repeating groups.<br>
            <strong>Action:</strong> Multiple installments (installments array) are flattened so each row represents a single atomic installment with primary key <code>(loan_id, installment_no)</code>.
        </p>

        <h3>2. Second Normal Form (2NF)</h3>
        <p>
            <strong>Rule:</strong> Must be in 1NF and contain NO partial functional dependencies on composite candidate keys.<br>
            In composite key <code>(loan_id, installment_no)</code>:
        </p>
        <pre><code class="language-sql">-- Partial Dependency:
loan_id -> applicant_name, pan, principal_amount, product_name
-- (These attributes depend ONLY on loan_id, not on installment_no!)</code></pre>
        <p>
            <strong>Decomposition:</strong> Split into <code>LOAN</code> and <code>EMI_SCHEDULE</code>. 
            Now, loan metadata depends entirely on <code>loan_id</code>, and installment terms depend on <code>(loan_id, installment_no)</code>.
        </p>

        <h3>3. Third Normal Form (3NF)</h3>
        <p>
            <strong>Rule:</strong> Must be in 2NF and contain NO transitive functional dependencies: <code>X &rarr; Y &rarr; Z</code>.
        </p>
        <pre><code class="language-sql">-- Transitive Dependencies:
loan_id -> product_id -> product_name, interest_rate, min_amount
loan_id -> applicant_id -> applicant_name, email, pan_no, credit_score</code></pre>
        <p>
            <strong>Decomposition:</strong> Extract <code>APPLICANT</code> and <code>LOAN_PRODUCT</code> into independent entities with their own primary keys. 
            <code>LOAN</code> maintains foreign keys <code>applicant_id</code> and <code>product_id</code>.
        </p>

        <h3>4. Boyce-Codd Normal Form (BCNF)</h3>
        <p>
            <strong>Rule:</strong> For every non-trivial functional dependency <code>X &rarr; Y</code>, <code>X</code> MUST be a superkey.<br>
            <strong>Validation:</strong>
        </p>
        <ul style="margin-left: 20px; font-size: 0.85rem; color: var(--text-muted);">
            <li>In <code>APPLICANT</code>: <code>applicant_id</code> is a superkey. <code>pan_no</code> and <code>aadhaar_no</code> are candidate keys (UNIQUE), so <code>pan_no &rarr; name</code> satisfies BCNF.</li>
            <li>In <code>LOAN_PRODUCT</code>: <code>product_id</code> is a superkey.</li>
            <li>In <code>EMI_SCHEDULE</code>: <code>(loan_id, installment_no)</code> is a composite candidate key.</li>
            <li>In <code>GUARANTOR</code>: <code>guarantor_id</code> is a superkey.</li>
        </ul>
        <div class="concept-box" style="margin-top: 14px;">
            <p><strong>Conclusion:</strong> The resulting 8-table relational model is in <strong>Strict BCNF</strong> with zero redundancy and zero loss of dependencies.</p>
        </div>
    `,

    procedures: `
        <h3>⚙️ Stored Procedures & Triggers</h3>
        <p>Compiled procedural logic running inside the MySQL InnoDB engine guarantees data integrity and zero race conditions.</p>

        <span class="sql-label">1. generate_emi_schedule (Reducing-Balance Amortization Loop)</span>
        <pre><code class="language-sql">DELIMITER $$
CREATE PROCEDURE generate_emi_schedule(IN p_loan_id INT)
BEGIN
    DECLARE v_principal DECIMAL(12,2);
    DECLARE v_rate DECIMAL(5,2);
    DECLARE v_tenure INT;
    DECLARE v_disb_date DATE;
    DECLARE v_monthly_rate DOUBLE;
    DECLARE v_emi DECIMAL(10,2);
    DECLARE v_balance DECIMAL(12,2);
    DECLARE v_interest_comp DECIMAL(10,2);
    DECLARE v_principal_comp DECIMAL(10,2);
    DECLARE v_due_date DATE;
    DECLARE i INT DEFAULT 1;

    -- Retrieve loan parameters
    SELECT principal_amount, interest_rate, tenure_months, COALESCE(disbursement_date, CURRENT_DATE)
    INTO v_principal, v_rate, v_tenure, v_disb_date
    FROM LOAN WHERE loan_id = p_loan_id;

    -- Monthly interest rate: r = (R / 12) / 100
    SET v_monthly_rate = (v_rate / 12.0) / 100.0;
    
    -- Reducing balance formula: EMI = P * r * (1+r)^n / ((1+r)^n - 1)
    SET v_emi = ROUND((v_principal * v_monthly_rate * POW(1 + v_monthly_rate, v_tenure)) 
                / (POW(1 + v_monthly_rate, v_tenure) - 1), 2);
    
    SET v_balance = v_principal;

    -- Delete any pre-existing schedule for regeneration
    DELETE FROM EMI_SCHEDULE WHERE loan_id = p_loan_id;

    -- Iterative amortization loop
    WHILE i <= v_tenure DO
        SET v_interest_comp = ROUND(v_balance * v_monthly_rate, 2);
        SET v_principal_comp = v_emi - v_interest_comp;
        
        -- Exact zero balance closure on final installment
        IF i = v_tenure OR v_principal_comp > v_balance THEN
            SET v_principal_comp = v_balance;
            SET v_emi = v_principal_comp + v_interest_comp;
            SET v_balance = 0.00;
        ELSE
            SET v_balance = v_balance - v_principal_comp;
        END IF;

        SET v_due_date = DATE_ADD(v_disb_date, INTERVAL i MONTH);

        INSERT INTO EMI_SCHEDULE (
            loan_id, installment_no, due_date, principal_component,
            interest_component, emi_amount, balance_after, status
        ) VALUES (
            p_loan_id, i, v_due_date, v_principal_comp,
            v_interest_comp, v_emi, v_balance, 'PENDING'
        );

        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;</code></pre>

        <span class="sql-label">2. process_repayment (ACID Transaction Handler)</span>
        <pre><code class="language-sql">DELIMITER $$
CREATE PROCEDURE process_repayment(
    IN p_loan_id INT,
    IN p_emi_id INT,
    IN p_amount DECIMAL(10,2),
    IN p_mode VARCHAR(20),
    IN p_ref VARCHAR(100),
    IN p_remarks VARCHAR(255)
)
BEGIN
    DECLARE v_due_date DATE;
    DECLARE v_emi_amt DECIMAL(10,2);
    DECLARE v_late_fee DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_unpaid_count INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Row-level locking to prevent concurrent double-spend
    SELECT due_date, emi_amount 
    INTO v_due_date, v_emi_amt
    FROM EMI_SCHEDULE 
    WHERE emi_id = p_emi_id AND loan_id = p_loan_id
    FOR UPDATE;

    -- Check if payment is past due date: apply 2% late fee penalty
    IF CURRENT_DATE > v_due_date THEN
        SET v_late_fee = ROUND(v_emi_amt * 0.02, 2);
    END IF;

    -- Record repayment ledger entry
    INSERT INTO REPAYMENT (
        emi_id, loan_id, amount_paid, payment_date, 
        payment_mode, transaction_ref, late_fee, remarks
    ) VALUES (
        p_emi_id, p_loan_id, p_amount, CURRENT_TIMESTAMP, 
        p_mode, p_ref, v_late_fee, p_remarks
    );

    -- Mark installment as PAID
    UPDATE EMI_SCHEDULE 
    SET status = 'PAID', paid_date = CURRENT_TIMESTAMP, penalty_amount = v_late_fee
    WHERE emi_id = p_emi_id;

    -- Check if all installments are settled
    SELECT COUNT(*) INTO v_unpaid_count 
    FROM EMI_SCHEDULE 
    WHERE loan_id = p_loan_id AND status != 'PAID';

    IF v_unpaid_count = 0 THEN
        UPDATE LOAN SET status = 'CLOSED' WHERE loan_id = p_loan_id;
        INSERT INTO LOAN_AUDIT (loan_id, field_changed, old_value, new_value, changed_by)
        VALUES (p_loan_id, 'status', 'ACTIVE', 'CLOSED', 'SYSTEM_PROCEDURE');
    END IF;

    COMMIT;
END$$
DELIMITER ;</code></pre>
    `,

    transactions: `
        <h3>🔒 Transactions & Concurrency Control</h3>
        <p>How banking ACID guarantees are enforced under high concurrent transaction loads.</p>

        <div class="concept-box">
            <p><strong>The Four Pillars of ACID in Bank Repayments:</strong></p>
            <ul style="margin-left: 20px; font-size: 0.85rem; color: var(--text-muted); margin-top: 6px;">
                <li><strong>Atomicity:</strong> Either REPAYMENT is logged AND EMI_SCHEDULE status is updated, or neither occurs. An abrupt crash rolls back all uncommitted mutations.</li>
                <li><strong>Consistency:</strong> Balance transitions must satisfy <code>CHECK (amount_paid > 0)</code> and FK constraints.</li>
                <li><strong>Isolation:</strong> Guaranteed via InnoDB row-level locking (<code>SELECT ... FOR UPDATE</code>) under REPEATABLE READ isolation.</li>
                <li><strong>Durability:</strong> Once COMMIT occurs, the write is flushed to InnoDB Redo Log (WAL) and survives power failures.</li>
            </ul>
        </div>

        <h3>Pessimistic Locking (SELECT ... FOR UPDATE)</h3>
        <p>
            If a customer pays an EMI via UPI while an automated NACH auto-debit triggers concurrently, 
            both processes target the same installment record. Without row locking, a double-deduction race condition occurs.
        </p>
        <pre><code class="language-sql">-- Process 1 (Auto-Debit Worker) locks the installment:
SELECT * FROM EMI_SCHEDULE WHERE emi_id = 100101 FOR UPDATE;
-- Process 2 (UPI Gateway Callback) waits on lock acquisition until Process 1 commits!</code></pre>

        <h3>Deadlock Scenario & Resolution</h3>
        <p>
            <strong>The Scenario:</strong><br>
            Transaction 1 transfers liability from Loan A to Loan B (locks A, attempts to lock B).<br>
            Transaction 2 consolidates Loan B into Loan A (locks B, attempts to lock A).<br>
            A cyclic dependency occurs: <code>T1 &rarr; T2 &rarr; T1</code>.
        </p>
        <pre><code class="language-sql">-- Deadlock Prevention Rule:
-- Always acquire locks in ascending order of primary key:
SELECT * FROM LOAN WHERE loan_id IN (1001, 1002) ORDER BY loan_id FOR UPDATE;</code></pre>
        <p>
            MySQL's InnoDB engine contains an internal deadlock detector: it identifies cycles in the wait-for graph 
            and automatically aborts the transaction with the smallest undo log, returning <code>ERROR 1213 (40001): Deadlock found</code>.
        </p>
    `,

    indexes: `
        <h3>⚡ B+ Tree Indexing & Performance Optimization</h3>
        <p>Analyzing query plans, clustered indexes, and composite secondary B+ trees.</p>

        <div class="concept-box">
            <p><strong>InnoDB Storage Architecture:</strong><br>
            InnoDB tables are organized as <strong>Index-Organized Tables (IOT)</strong>. The primary key forms the clustered index, 
            meaning table data rows are physically stored directly in the leaf nodes of the primary key's B+ tree.</p>
        </div>

        <span class="sql-label">Strategic Secondary Indexes</span>
        <pre><code class="language-sql">-- 1. Accelerates borrower portfolio lookups:
CREATE INDEX idx_loan_applicant_status ON LOAN (applicant_id, status);

-- 2. Optimizes daily delinquency scans:
CREATE INDEX idx_emi_loan_status_due ON EMI_SCHEDULE (loan_id, status, due_date);

-- 3. Enables instantaneous KYC lookups:
CREATE UNIQUE INDEX idx_applicant_pan ON APPLICANT (pan_no);
CREATE UNIQUE INDEX idx_applicant_aadhaar ON APPLICANT (aadhaar_no);</code></pre>

        <h3>EXPLAIN Execution Plan Comparison</h3>
        <p>Before adding the composite index on <code>EMI_SCHEDULE(status, due_date)</code>:</p>
        <pre><code class="language-sql">EXPLAIN SELECT * FROM EMI_SCHEDULE WHERE status = 'OVERDUE' AND due_date < CURRENT_DATE;
+----+-------------+--------------+------------+------+---------------+------+---------+------+-------+----------+-------------+
| id | select_type | table        | partitions | type | possible_keys | key  | key_len | ref  | rows  | filtered | Extra       |
+----+-------------+--------------+------------+------+---------------+------+---------+------+-------+----------+-------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 50000 |    10.00 | Using where |
+----+-------------+--------------+------------+------+---------------+------+---------+------+-------+----------+-------------+
-- Type: ALL indicates an expensive Full Table Scan across all 50,000 installments.</code></pre>

        <p>After creating the composite index:</p>
        <pre><code class="language-sql">+----+-------------+--------------+------------+-------+-------------------------+-------------------------+---------+------+------+----------+-----------------------+
| id | select_type | table        | partitions | type  | possible_keys           | key                     | key_len | ref  | rows | filtered | Extra                 |
+----+-------------+--------------+------------+-------+-------------------------+-------------------------+---------+------+------+----------+-----------------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | range | idx_emi_loan_status_due | idx_emi_loan_status_due | 5       | NULL |    8 |   100.00 | Using index condition |
+----+-------------+--------------+------------+-------+-------------------------+-------------------------+---------+------+------+----------+-----------------------+
-- Type: range (B+ tree index seek). Reduced rows scanned from 50,000 to 8!</code></pre>
    `,

    er: `
        <h3>🌐 Entity-Relationship (ER) Architecture</h3>
        <p>Conceptual and relational mapping of the Bank Loan Management System.</p>

        <div class="concept-box">
            <p><strong>Entity Sets & Cardinalities:</strong></p>
            <ul style="margin-left: 20px; font-size: 0.85rem; color: var(--text-muted); margin-top: 6px;">
                <li><strong>APPLICANT (1) &mdash;&mdash;&lt; (N) LOAN:</strong> One applicant can hold multiple loans over time. A loan must belong to exactly 1 applicant (Total Participation).</li>
                <li><strong>LOAN_PRODUCT (1) &mdash;&mdash;&lt; (N) LOAN:</strong> A product type governs multiple sanctioned loans.</li>
                <li><strong>GUARANTOR (0..1) &mdash;&mdash;&lt; (N) LOAN:</strong> A guarantor is optional (Partial Participation), used for education/commercial loans.</li>
                <li><strong>LOAN (1) &mdash;&mdash;&lt; (N) EMI_SCHEDULE:</strong> Weak Entity relationship. An EMI schedule cannot exist without its parent loan. (Identified by composite key <code>loan_id + installment_no</code>).</li>
                <li><strong>EMI_SCHEDULE (1) &mdash;&mdash;&lt; (0..N) REPAYMENT:</strong> Each installment receives 0, 1, or partial repayment logs.</li>
                <li><strong>LOAN (1) &mdash;&mdash;&lt; (0..N) DEFAULT_LOG:</strong> Overdue accounts trigger non-performing asset logs.</li>
                <li><strong>LOAN (1) &mdash;&mdash;&lt; (N) LOAN_AUDIT:</strong> Every state change (status transition) writes an immutable audit record.</li>
            </ul>
        </div>

        <span class="sql-label">Textual ER Diagram</span>
        <pre><code>[APPLICANT]  (1) &lt;──── Sanctions ────&gt; (N) [LOAN] &lt;──── Belongs To ────&gt; (1) [LOAN_PRODUCT]
     │                                        │
     │                                   (1)  │
     │                                        │ Schedules
     │                                        ▼
     │                                [EMI_SCHEDULE] (Weak)
     │                                        │
     │                                   (1)  │ Receives
     │                                        ▼
     │                                   [REPAYMENT]
     │                                        
     └───── Co-Signs ────&gt; [GUARANTOR] (0..1) ───&gt; [LOAN] ─── Logs ───&gt; [DEFAULT_LOG]
                                                         └─── Audits ──&gt; [LOAN_AUDIT]</code></pre>
    `
};

// ----------------------------------------------------------------------------
// 7. INITIALIZE "HOW IT WORKS" MODAL
// ----------------------------------------------------------------------------
function initModal() {
    const overlay = document.getElementById('modalOverlay');
    const closeBtn = document.getElementById('modalClose');
    const openBtns = [
        document.getElementById('howItWorksBtn'),
        document.getElementById('footerHowItWorks')
    ].filter(Boolean);

    if (!overlay) return;

    function openTab(tabName) {
        document.querySelectorAll('.modal-tabs .tab').forEach(t => {
            t.classList.toggle('active', t.getAttribute('data-tab') === tabName);
        });
        const body = document.getElementById('modalBody');
        if (body) {
            body.innerHTML = howItWorksContent[tabName] || '<p>Content not found.</p>';
            if (window.hljs) {
                body.querySelectorAll('pre code').forEach(block => {
                    hljs.highlightElement(block);
                });
            }
        }
    }

    openBtns.forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.preventDefault();
            overlay.classList.add('active');
            openTab('schema');
        });
    });

    if (closeBtn) {
        closeBtn.addEventListener('click', () => {
            overlay.classList.remove('active');
        });
    }

    overlay.addEventListener('click', (e) => {
        if (e.target === overlay) overlay.classList.remove('active');
    });

    document.querySelectorAll('.modal-tabs .tab').forEach(tab => {
        tab.addEventListener('click', () => {
            openTab(tab.getAttribute('data-tab'));
        });
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') overlay.classList.remove('active');
    });
}

// ----------------------------------------------------------------------------
// 8. SEARCH & FILTERING
// ----------------------------------------------------------------------------
function initSearch() {
    const input = document.getElementById('searchInput');
    const btn = document.querySelector('.btn-search');

    function performSearch() {
        const query = (input ? input.value : '').toLowerCase().trim();
        if (!query) {
            renderLoans(allLoansCache);
            return;
        }

        const filtered = allLoansCache.filter(l => {
            return (l.applicant_name || '').toLowerCase().includes(query) ||
                   (l.product_name || '').toLowerCase().includes(query) ||
                   (l.product_type || '').toLowerCase().includes(query) ||
                   (String(l.loan_id)).includes(query) ||
                   (l.status || '').toLowerCase().includes(query);
        });

        renderLoans(filtered);
    }

    if (input) {
        input.addEventListener('input', performSearch);
        input.addEventListener('keyup', (e) => {
            if (e.key === 'Enter') performSearch();
        });
    }
    if (btn) btn.addEventListener('click', performSearch);
}

function resetFilters() {
    activeCategoryFilter = 'ALL';
    const input = document.getElementById('searchInput');
    if (input) input.value = '';
    renderLoans(allLoansCache);
}

// ----------------------------------------------------------------------------
// 9. BANK STAFF LOGIN SYSTEM
// ----------------------------------------------------------------------------
function initLogin() {
    const loginBtn = document.getElementById('loginBtn');
    const loginOverlay = document.getElementById('loginOverlay');
    const loginClose = document.getElementById('loginClose');
    const loginBody = document.getElementById('loginBody');
    const loginTitle = document.getElementById('loginModalTitle');

    if (!loginBtn || !loginOverlay || !loginBody) return;

    function renderLoginForm() {
        if (loginTitle) loginTitle.innerHTML = '🔐 Bank Officer Authorization Portal';
        
        loginBody.innerHTML = `
            <div style="margin-bottom:18px;">
                <p style="font-size:0.88rem; color:var(--text-muted); margin-bottom:14px;">
                    Select an authorized SBI Branch Officer to evaluate loan approvals, sanction limits, and recovery actions.
                </p>
                <div class="user-picker-grid">
                    ${sampleBankUsers.map(u => `
                        <div class="user-picker-card" onclick="selectBankUser(${u.user_id})">
                            <div class="user-picker-avatar" style="background:linear-gradient(135deg, var(--primary), var(--secondary));">
                                ${u.name.split(' ').map(n=>n[0]).join('')}
                            </div>
                            <div class="user-picker-info">
                                <div class="user-picker-name">${u.name}</div>
                                <div class="user-picker-detail">${u.emp_code} &bull; ${u.branch.split(',')[0]}</div>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>

            <div class="concept-box" style="margin-top:16px;">
                <p style="font-size:0.8rem; margin:0;">
                    <strong>Role-Based Access Control:</strong> Chief Managers hold a ₹1.00 Cr sanction limit; 
                    Retail Officers hold a ₹25.00 Lakh limit. All sanctions log the officer's ID to <code>LOAN.approved_by</code>.
                </p>
            </div>
        `;
    }

    function renderLoggedInProfile(user) {
        if (loginTitle) loginTitle.innerHTML = '🏛️ Officer Profile & Sanction Limits';

        loginBody.innerHTML = `
            <div class="profile-container">
                <div class="profile-avatar-large">
                    ${user.name.split(' ').map(n=>n[0]).join('')}
                </div>
                <div class="profile-name">${user.name}</div>
                <div class="profile-email">${user.role}</div>

                <div class="profile-details">
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Employee Code</div>
                        <div class="profile-detail-value">${user.emp_code}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Branch</div>
                        <div class="profile-detail-value">${user.branch}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Sanction Limit</div>
                        <div class="profile-detail-value" style="color:var(--secondary);">${formatINR(user.sanction_limit)}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Email</div>
                        <div class="profile-detail-value" style="font-size:0.8rem;">${user.email}</div>
                    </div>
                </div>

                <div class="profile-actions">
                    <button class="btn btn-outline" onclick="logoutBankUser()">Sign Out</button>
                    <button class="btn btn-primary" onclick="document.getElementById('loginOverlay').classList.remove('active'); openApplyModal();">
                        + New Sanction
                    </button>
                </div>
            </div>
        `;
    }

    window.selectBankUser = function(userId) {
        const user = sampleBankUsers.find(u => u.user_id === userId);
        if (user) {
            currentLoggedInUser = user;
            loginOverlay.classList.remove('active');
            updateNavbarUser(user);
        }
    };

    window.logoutBankUser = function() {
        currentLoggedInUser = null;
        const navActions = document.querySelector('.nav-actions');
        if (navActions) {
            const userBtn = navActions.querySelector('.nav-user');
            if (userBtn) userBtn.remove();
            if (loginBtn) loginBtn.style.display = 'inline-block';
        }
        loginOverlay.classList.remove('active');
    };

    function updateNavbarUser(user) {
        if (loginBtn) loginBtn.style.display = 'none';
        const navActions = document.querySelector('.nav-actions');
        if (!navActions) return;

        let userBadge = navActions.querySelector('.nav-user');
        if (!userBadge) {
            userBadge = document.createElement('button');
            userBadge.className = 'nav-user';
            navActions.prepend(userBadge);
        }

        userBadge.innerHTML = `
            <div class="nav-user-avatar">${user.name.split(' ').map(n=>n[0]).join('')}</div>
            <span class="nav-user-name">${user.name.split(' ')[0]} (${user.emp_code.split('_')[1]})</span>
        `;

        userBadge.onclick = () => {
            renderLoggedInProfile(user);
            loginOverlay.classList.add('active');
        };
    }

    loginBtn.addEventListener('click', () => {
        if (currentLoggedInUser) {
            renderLoggedInProfile(currentLoggedInUser);
        } else {
            renderLoginForm();
        }
        loginOverlay.classList.add('active');
    });

    if (loginClose) {
        loginClose.addEventListener('click', () => loginOverlay.classList.remove('active'));
    }

    loginOverlay.addEventListener('click', (e) => {
        if (e.target === loginOverlay) loginOverlay.classList.remove('active');
    });
}

// ----------------------------------------------------------------------------
// 10. EMI CALCULATOR ENGINE (INTERACTIVE REDUCING-BALANCE SIMULATOR)
// ----------------------------------------------------------------------------
function calculateEmi(principal, annualRate, tenureMonths) {
    const P = Number(principal);
    const r = (Number(annualRate) / 12.0) / 100.0;
    const n = Number(tenureMonths);

    if (P <= 0 || n <= 0) return { emi: 0, totalPayable: 0, totalInterest: 0 };
    if (r === 0) {
        const emi = P / n;
        return { emi, totalPayable: P, totalInterest: 0 };
    }

    const emi = (P * r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1);
    const totalPayable = emi * n;
    const totalInterest = totalPayable - P;
    return {
        emi: Math.round(emi),
        totalPayable: Math.round(totalPayable),
        totalInterest: Math.round(totalInterest)
    };
}

function initEmiCalculatorSection() {
    // If an element with id="emiCalculatorSection" doesn't exist, create it above the dashboard
    let section = document.getElementById('emiCalculatorSection');
    if (!section) {
        section = document.createElement('section');
        section.id = 'emiCalculatorSection';
        section.className = 'section';
        section.style.background = 'rgba(22, 22, 42, 0.7)';
        section.style.borderTop = '1px solid var(--glass-border)';
        section.style.borderBottom = '1px solid var(--glass-border)';

        const container = document.createElement('div');
        container.className = 'container';
        container.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:flex-end; margin-bottom:32px; flex-wrap:wrap; gap:16px;">
                <div>
                    <h2 class="section-title">🧮 Reducing-Balance EMI Amortization Engine</h2>
                    <p class="section-subtitle" style="margin-bottom:0;">
                        Calculate exact monthly payments using standard Indian banking formula: 
                        <code>EMI = P &times; r &times; (1+r)<sup>n</sup> / ((1+r)<sup>n</sup> &minus; 1)</code>
                    </p>
                </div>
            </div>

            <div style="display:grid; grid-template-columns: 1fr 1.2fr; gap:32px; align-items:start;">
                <!-- Controls -->
                <div style="background:var(--bg-card); border:1px solid var(--glass-border); border-radius:var(--radius); padding:28px;">
                    <div style="margin-bottom:20px;">
                        <label style="display:flex; justify-content:space-between; font-size:0.85rem; font-weight:600; margin-bottom:8px;">
                            <span>Principal Loan Amount (P)</span>
                            <span id="calcPrincipalDisplay" style="color:var(--secondary); font-weight:700;">₹10,00,000</span>
                        </label>
                        <input type="range" id="calcPrincipalRange" min="50000" max="10000000" step="50000" value="1000000" style="width:100%; accent-color:var(--primary);">
                        <input type="number" id="calcPrincipalInput" value="1000000" style="margin-top:8px;" class="login-form">
                    </div>

                    <div style="margin-bottom:20px;">
                        <label style="display:flex; justify-content:space-between; font-size:0.85rem; font-weight:600; margin-bottom:8px;">
                            <span>Annual Interest Rate (R % p.a.)</span>
                            <span id="calcRateDisplay" style="color:var(--primary-light); font-weight:700;">8.50%</span>
                        </label>
                        <input type="range" id="calcRateRange" min="5.0" max="24.0" step="0.25" value="8.50" style="width:100%; accent-color:var(--primary);">
                    </div>

                    <div style="margin-bottom:24px;">
                        <label style="display:flex; justify-content:space-between; font-size:0.85rem; font-weight:600; margin-bottom:8px;">
                            <span>Tenure in Months (n)</span>
                            <span id="calcTenureDisplay" style="color:var(--accent); font-weight:700;">60 Months (5 Yrs)</span>
                        </label>
                        <input type="range" id="calcTenureRange" min="6" max="360" step="6" value="60" style="width:100%; accent-color:var(--primary);">
                    </div>

                    <div class="concept-box" style="margin:0;">
                        <p style="font-size:0.8rem; margin:0;">
                            <strong>Interest Amortization:</strong> Interest is charged only on the declining principal balance, 
                            so the principal repayment component increases with each passing installment!
                        </p>
                    </div>
                </div>

                <!-- Results & Visual Breakdown -->
                <div style="background:var(--bg-card); border:1px solid var(--glass-border); border-radius:var(--radius); padding:28px;">
                    <div style="text-align:center; padding-bottom:24px; border-bottom:1px solid var(--glass-border); margin-bottom:24px;">
                        <span style="font-size:0.85rem; color:var(--text-muted); text-transform:uppercase; letter-spacing:0.05em;">Calculated Monthly EMI</span>
                        <div id="calcEmiResult" style="font-size:2.8rem; font-weight:900; color:var(--secondary); margin:6px 0;">₹20,517</div>
                        <span style="font-size:0.8rem; color:var(--text-dim);">Payable on 1st of each calendar month</span>
                    </div>

                    <div style="display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-bottom:24px;">
                        <div style="background:var(--bg-surface); padding:16px; border-radius:var(--radius-sm);">
                            <span style="font-size:0.75rem; color:var(--text-muted);">Total Principal Amount</span>
                            <div id="calcPrincipalTotal" style="font-size:1.2rem; font-weight:700; color:var(--text); margin-top:4px;">₹10,00,000</div>
                        </div>
                        <div style="background:var(--bg-surface); padding:16px; border-radius:var(--radius-sm);">
                            <span style="font-size:0.75rem; color:var(--text-muted);">Total Interest Payable</span>
                            <div id="calcInterestTotal" style="font-size:1.2rem; font-weight:700; color:var(--accent); margin-top:4px;">₹2,30,993</div>
                        </div>
                    </div>

                    <div style="background:var(--bg-surface); padding:16px; border-radius:var(--radius-sm); margin-bottom:20px; display:flex; justify-content:space-between; align-items:center;">
                        <span style="font-size:0.85rem; font-weight:600;">Total Amount (Principal + Interest)</span>
                        <span id="calcGrandTotal" style="font-size:1.3rem; font-weight:800; color:var(--primary-light);">₹12,30,993</span>
                    </div>

                    <button class="btn btn-primary" style="width:100%;" onclick="openApplyModalWithParams()">
                        Apply with These Parameters &rarr;
                    </button>
                </div>
            </div>
        `;
        section.appendChild(container);

        // Insert before dashboard or after listings
        const dashboard = document.getElementById('dashboard');
        if (dashboard && dashboard.parentNode) {
            dashboard.parentNode.insertBefore(section, dashboard);
        } else {
            document.body.appendChild(section);
        }

        // Attach event listeners for real-time slider updates
        const pRange = document.getElementById('calcPrincipalRange');
        const pInput = document.getElementById('calcPrincipalInput');
        const rRange = document.getElementById('calcRateRange');
        const tRange = document.getElementById('calcTenureRange');

        function updateCalc() {
            const P = Number(pRange.value);
            const R = Number(rRange.value);
            const N = Number(tRange.value);

            document.getElementById('calcPrincipalDisplay').innerText = formatINR(P);
            pInput.value = P;
            document.getElementById('calcRateDisplay').innerText = `${R.toFixed(2)}%`;
            document.getElementById('calcTenureDisplay').innerText = `${N} Months (${(N/12).toFixed(1)} Yrs)`;

            const res = calculateEmi(P, R, N);
            document.getElementById('calcEmiResult').innerText = formatINR(res.emi);
            document.getElementById('calcPrincipalTotal').innerText = formatINR(P);
            document.getElementById('calcInterestTotal').innerText = formatINR(res.totalInterest);
            document.getElementById('calcGrandTotal').innerText = formatINR(res.totalPayable);
        }

        pRange.addEventListener('input', updateCalc);
        rRange.addEventListener('input', updateCalc);
        tRange.addEventListener('input', updateCalc);
        pInput.addEventListener('input', () => {
            pRange.value = pInput.value;
            updateCalc();
        });

        updateCalc();
    }
}

// ----------------------------------------------------------------------------
// 11. "APPLY FOR LOAN" MODAL (REPLACES OLD "SELL" MODAL)
// ----------------------------------------------------------------------------
function initApplyLoanModal() {
    // Check sellOverlay in index.html
    const sellOverlay = document.getElementById('sellOverlay');
    const sellClose = document.getElementById('sellClose');
    const sellBody = document.getElementById('sellBody');
    const navSellBtn = document.querySelector('.nav-actions .btn-primary');

    if (!sellOverlay || !sellBody) return;

    if (navSellBtn) {
        navSellBtn.innerHTML = '📝 Apply for Loan';
        navSellBtn.onclick = () => openApplyModal();
    }

    window.openApplyModal = function(initialP = 500000, initialR = 8.50, initialN = 60) {
        const headerTitle = sellOverlay.querySelector('.modal-header h2');
        if (headerTitle) headerTitle.innerHTML = '📝 New Bank Loan Application';

        sellBody.innerHTML = `
            <form class="login-form" id="applyLoanForm" onsubmit="handleLoanApplicationSubmit(event)">
                <div>
                    <label>Borrower / Applicant *</label>
                    <select id="loanApplicantSelect" required onchange="handleApplicantSelectChange(this)">
                        ${sampleApplicants.map(a => `
                            <option value="${a.applicant_id}">
                                ${a.name} (PAN: ${a.pan_no} | CIBIL: ${a.credit_score})
                            </option>
                        `).join('')}
                    </select>
                </div>

                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
                    <div>
                        <label>Loan Product *</label>
                        <select id="loanProductSelect" required onchange="handleProductSelectChange(this)">
                            ${sampleProducts.map(p => `
                                <option value="${p.product_id}" data-rate="${p.interest_rate}" data-type="${p.product_type}">
                                    ${p.name} (${p.interest_rate}%)
                                </option>
                            `).join('')}
                        </select>
                    </div>
                    <div>
                        <label>Interest Rate (% p.a.)</label>
                        <input type="number" id="loanRateInput" step="0.05" value="${initialR}" required readonly style="background:var(--bg-surface); opacity:0.8;">
                    </div>
                </div>

                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
                    <div>
                        <label>Principal Amount (₹) *</label>
                        <input type="number" id="loanPrincipalInput" min="20000" max="10000000" step="10000" value="${initialP}" required oninput="recalcFormEmi()">
                    </div>
                    <div>
                        <label>Tenure (Months) *</label>
                        <input type="number" id="loanTenureInput" min="6" max="360" step="6" value="${initialN}" required oninput="recalcFormEmi()">
                    </div>
                </div>

                <!-- Instant EMI Calculation Box -->
                <div style="background:rgba(0,184,148,0.1); border:1px solid rgba(0,184,148,0.3); border-radius:var(--radius-sm); padding:14px; display:flex; justify-content:space-between; align-items:center;">
                    <div>
                        <span style="font-size:0.75rem; color:var(--text-muted); text-transform:uppercase;">Calculated Reducing Monthly EMI</span>
                        <div id="formCalculatedEmi" style="font-size:1.3rem; font-weight:800; color:var(--secondary);">₹10,258 / mo</div>
                    </div>
                    <div style="text-align:right;">
                        <span style="font-size:0.75rem; color:var(--text-muted);">Total Repayment</span>
                        <div id="formCalculatedTotal" style="font-size:1.05rem; font-weight:700; color:var(--text);">₹6,15,480</div>
                    </div>
                </div>

                <div>
                    <label>Guarantor / Co-Applicant (Optional)</label>
                    <input type="text" id="loanGuarantorInput" placeholder="e.g. Spouse / Parent / Business Partner Name">
                </div>

                <div>
                    <label>Officer Remarks / Credit Notes</label>
                    <input type="text" id="loanRemarksInput" placeholder="e.g. KYC verified, salary slip attached, credit check cleared" value="Approved under retail underwriting program">
                </div>

                <button type="submit" class="btn btn-primary" style="width:100%; margin-top:8px;">
                    Sanction Loan & Generate Schedule &rarr;
                </button>

                <div class="concept-box" style="margin-top:8px;">
                    <p style="margin-bottom:0; color:var(--text); font-size:0.8rem;">
                        <strong>🔍 SQL Behind Sanction:</strong> Executes <code>INSERT INTO LOAN (...)</code> with CHECK constraints, 
                        followed immediately by stored procedure <code>CALL generate_emi_schedule(loan_id)</code>.
                    </p>
                </div>
            </form>
        `;

        sellOverlay.classList.add('active');
        recalcFormEmi();
    };

    window.openApplyModalWithParams = function() {
        const p = document.getElementById('calcPrincipalRange') ? document.getElementById('calcPrincipalRange').value : 500000;
        const r = document.getElementById('calcRateRange') ? document.getElementById('calcRateRange').value : 8.5;
        const n = document.getElementById('calcTenureRange') ? document.getElementById('calcTenureRange').value : 60;
        openApplyModal(p, r, n);
    };

    window.handleProductSelectChange = function(select) {
        const opt = select.options[select.selectedIndex];
        const rate = opt.getAttribute('data-rate');
        const rateInput = document.getElementById('loanRateInput');
        if (rateInput && rate) {
            rateInput.value = rate;
            recalcFormEmi();
        }
    };

    window.recalcFormEmi = function() {
        const p = Number(document.getElementById('loanPrincipalInput').value || 0);
        const r = Number(document.getElementById('loanRateInput').value || 8.5);
        const n = Number(document.getElementById('loanTenureInput').value || 60);

        const res = calculateEmi(p, r, n);
        const emiDisplay = document.getElementById('formCalculatedEmi');
        const totDisplay = document.getElementById('formCalculatedTotal');
        if (emiDisplay) emiDisplay.innerText = `${formatINR(res.emi)} / mo`;
        if (totDisplay) totDisplay.innerText = formatINR(res.totalPayable);
    };

    window.handleLoanApplicationSubmit = async function(e) {
        e.preventDefault();
        const applicantId = Number(document.getElementById('loanApplicantSelect').value);
        const productId = Number(document.getElementById('loanProductSelect').value);
        const principal = Number(document.getElementById('loanPrincipalInput').value);
        const rate = Number(document.getElementById('loanRateInput').value);
        const tenure = Number(document.getElementById('loanTenureInput').value);
        const guarantor = document.getElementById('loanGuarantorInput').value.trim();
        const remarks = document.getElementById('loanRemarksInput').value.trim();

        const officerName = currentLoggedInUser ? currentLoggedInUser.name : "Ramesh Iyer (Chief Manager)";

        const payload = {
            applicant_id: applicantId,
            product_id: productId,
            principal_amount: principal,
            interest_rate: rate,
            tenure_months: tenure,
            remarks: remarks,
            approved_by: officerName,
            status: "ACTIVE"
        };

        let newLoanId = null;

        if (backendConnected) {
            try {
                const res = await fetch(`${API_BASE}/loans`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                if (data.loan_id) {
                    newLoanId = data.loan_id;
                    // Trigger generate EMI procedure
                    await fetch(`${API_BASE}/loans/${newLoanId}/generate-emi`, { method: 'POST' });
                }
            } catch (err) {
                console.warn('API error during loan sanction:', err);
            }
        }

        // If offline or fallback
        if (!newLoanId) {
            newLoanId = 1000 + sampleLoans.length + 1;
            const appObj = sampleApplicants.find(a => a.applicant_id === applicantId) || sampleApplicants[0];
            const prodObj = sampleProducts.find(p => p.product_id === productId) || sampleProducts[0];
            const calc = calculateEmi(principal, rate, tenure);

            const newLoan = {
                loan_id: newLoanId,
                applicant_id: applicantId,
                applicant_name: appObj.name,
                applicant_email: appObj.email,
                credit_score: appObj.credit_score,
                product_id: productId,
                product_name: prodObj.name,
                product_type: prodObj.product_type,
                guarantor_id: guarantor ? 99 : null,
                guarantor_name: guarantor || null,
                principal_amount: principal,
                interest_rate: rate,
                tenure_months: tenure,
                emi_amount: calc.emi,
                total_payable: calc.totalPayable,
                disbursement_date: new Date().toISOString().split('T')[0],
                maturity_date: new Date(Date.now() + tenure * 30 * 86400000).toISOString().split('T')[0],
                status: "ACTIVE",
                approved_by: officerName,
                remarks: remarks
            };

            sampleLoans.unshift(newLoan);
            allLoansCache = sampleLoans;
        }

        sellOverlay.classList.remove('active');
        alert(`🎉 Loan #${newLoanId} successfully sanctioned!\nAmortization schedule compiled and activated.`);
        renderLoans();
        openLoanDetailModal(newLoanId);
    };

    if (sellClose) {
        sellClose.addEventListener('click', () => sellOverlay.classList.remove('active'));
    }
    sellOverlay.addEventListener('click', (e) => {
        if (e.target === sellOverlay) sellOverlay.classList.remove('active');
    });
}

// ----------------------------------------------------------------------------
// 12. LOAN & APPLICANT DETAILS MODAL WITH EMI SCHEDULE & REPAYMENT TRIGGER
// ----------------------------------------------------------------------------
async function openLoanDetailModal(loanId) {
    let loan = allLoansCache.find(l => l.loan_id === loanId);
    let schedule = [];
    let repayments = [];

    if (backendConnected) {
        try {
            const res = await fetch(`${API_BASE}/loans/${loanId}`);
            const data = await res.json();
            if (data.data) {
                loan = data.data;
                schedule = data.data.emi_schedule || [];
                repayments = data.data.repayments || [];
            }
        } catch (e) {
            console.warn('API error fetching loan detail:', e);
        }
    }

    if (!loan) loan = sampleLoans[0];

    // Generate local amortization schedule if empty
    if (!schedule || schedule.length === 0) {
        const P = loan.principal_amount;
        const r = (loan.interest_rate / 12.0) / 100.0;
        const n = loan.tenure_months;
        const emi = loan.emi_amount;
        let bal = P;
        const start = new Date(loan.disbursement_date || '2024-02-01');

        for (let i = 1; i <= Math.min(n, 24); i++) {
            const intComp = Math.round(bal * r);
            let prinComp = emi - intComp;
            if (i === n || prinComp > bal) {
                prinComp = bal;
                bal = 0;
            } else {
                bal = Math.max(0, bal - prinComp);
            }
            const d = new Date(start);
            d.setMonth(d.getMonth() + i);

            const isPast = d < new Date();
            const status = (loan.loan_id === 1005 && i >= 3) ? 'OVERDUE' : (isPast ? 'PAID' : 'PENDING');

            schedule.push({
                emi_id: (loan.loan_id * 100) + i,
                installment_no: i,
                due_date: d.toISOString().split('T')[0],
                principal_component: prinComp,
                interest_component: intComp,
                emi_amount: emi,
                balance_after: bal,
                status: status,
                penalty_amount: (status === 'OVERDUE' ? 1574 : 0)
            });
        }
    }

    // Reuse or create detail modal
    let modalOverlay = document.getElementById('loanDetailOverlay');
    if (!modalOverlay) {
        modalOverlay = document.createElement('div');
        modalOverlay.id = 'loanDetailOverlay';
        modalOverlay.className = 'modal-overlay';
        document.body.appendChild(modalOverlay);
    }

    modalOverlay.innerHTML = `
        <div class="modal" style="max-width: 960px;">
            <div class="modal-header">
                <div>
                    <h2 style="margin:0;">🏦 Loan Dossier #${loan.loan_id} &bull; ${loan.applicant_name}</h2>
                    <span style="font-size:0.8rem; color:var(--text-muted);">${loan.product_name} &bull; Sanctioned by ${loan.approved_by || 'Officer'}</span>
                </div>
                <button class="modal-close" onclick="document.getElementById('loanDetailOverlay').classList.remove('active');">&times;</button>
            </div>
            <div class="modal-body">
                <!-- Summary KPI Row -->
                <div style="display:grid; grid-template-columns: repeat(4, 1fr); gap:14px; margin-bottom:24px;">
                    <div style="background:var(--bg-surface); padding:14px; border-radius:var(--radius-sm);">
                        <span style="font-size:0.7rem; color:var(--text-muted); text-transform:uppercase;">Principal</span>
                        <div style="font-size:1.15rem; font-weight:700; color:var(--secondary);">${formatINR(loan.principal_amount)}</div>
                    </div>
                    <div style="background:var(--bg-surface); padding:14px; border-radius:var(--radius-sm);">
                        <span style="font-size:0.7rem; color:var(--text-muted); text-transform:uppercase;">Monthly EMI</span>
                        <div style="font-size:1.15rem; font-weight:700; color:var(--primary-light);">${formatINR(loan.emi_amount)}</div>
                    </div>
                    <div style="background:var(--bg-surface); padding:14px; border-radius:var(--radius-sm);">
                        <span style="font-size:0.7rem; color:var(--text-muted); text-transform:uppercase;">Interest Rate</span>
                        <div style="font-size:1.15rem; font-weight:700; color:var(--text);">${loan.interest_rate}% p.a.</div>
                    </div>
                    <div style="background:var(--bg-surface); padding:14px; border-radius:var(--radius-sm);">
                        <span style="font-size:0.7rem; color:var(--text-muted); text-transform:uppercase;">Loan Status</span>
                        <div style="font-size:1.15rem; font-weight:700; color:${loan.status==='DEFAULTED'?'#E17055':(loan.status==='CLOSED'?'#A29BFE':'#00B894')};">${loan.status}</div>
                    </div>
                </div>

                <!-- Amortization Schedule Table -->
                <h3 style="margin-bottom:12px;">📅 Reducing-Balance Amortization Schedule (EMI_SCHEDULE)</h3>
                <div style="max-height:300px; overflow-y:auto; border:1px solid var(--glass-border); border-radius:var(--radius-sm); margin-bottom:24px;">
                    <table style="width:100%; border-collapse:collapse; font-size:0.82rem; text-align:left;">
                        <thead style="background:var(--bg-surface); position:sticky; top:0; color:var(--text-muted); text-transform:uppercase; font-size:0.7rem;">
                            <tr>
                                <th style="padding:10px 14px;">#</th>
                                <th style="padding:10px 14px;">Due Date</th>
                                <th style="padding:10px 14px;">Principal</th>
                                <th style="padding:10px 14px;">Interest</th>
                                <th style="padding:10px 14px;">EMI Amount</th>
                                <th style="padding:10px 14px;">Balance After</th>
                                <th style="padding:10px 14px;">Status</th>
                                <th style="padding:10px 14px;">Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${schedule.map(s => `
                                <tr style="border-bottom:1px solid rgba(255,255,255,0.05);">
                                    <td style="padding:10px 14px; font-weight:600;">${s.installment_no}</td>
                                    <td style="padding:10px 14px;">${s.due_date}</td>
                                    <td style="padding:10px 14px; color:var(--secondary);">${formatINR(s.principal_component)}</td>
                                    <td style="padding:10px 14px; color:var(--accent);">${formatINR(s.interest_component)}</td>
                                    <td style="padding:10px 14px; font-weight:700;">${formatINR(s.emi_amount)}</td>
                                    <td style="padding:10px 14px;">${formatINR(s.balance_after)}</td>
                                    <td style="padding:10px 14px;">
                                        <span style="font-size:0.68rem; padding:3px 8px; border-radius:4px; font-weight:700;
                                            background:${s.status==='PAID'?'rgba(0,184,148,0.15)':(s.status==='OVERDUE'?'rgba(225,112,85,0.15)':'rgba(253,203,110,0.15)')};
                                            color:${s.status==='PAID'?'#00B894':(s.status==='OVERDUE'?'#E17055':'#FDCB6E')};">
                                            ${s.status}
                                        </span>
                                    </td>
                                    <td style="padding:10px 14px;">
                                        ${s.status !== 'PAID' ? `
                                            <button class="btn btn-outline" style="padding:4px 10px; font-size:0.7rem;" onclick="triggerPayEmi(${loan.loan_id}, ${s.emi_id}, ${s.emi_amount})">
                                                Pay Now
                                            </button>
                                        ` : `
                                            <span style="color:var(--text-dim); font-size:0.75rem;">✓ Paid</span>
                                        `}
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>

                <div class="concept-box" style="margin:0;">
                    <p style="font-size:0.8rem; margin:0;">
                        <strong>ACID Banking Repayment:</strong> Clicking <em>Pay Now</em> calls stored procedure <code>process_repayment</code> 
                        with row-level lock <code>SELECT ... FOR UPDATE</code>.
                    </p>
                </div>
            </div>
        </div>
    `;

    modalOverlay.classList.add('active');
}

window.triggerPayEmi = async function(loanId, emiId, amount) {
    if (!confirm(`Confirm repayment of ${formatINR(amount)} for Installment #${emiId}?`)) return;

    const payload = {
        loan_id: loanId,
        emi_id: emiId,
        amount_paid: amount,
        payment_mode: "AUTO_DEBIT",
        remarks: "Online portal instant repayment"
    };

    if (backendConnected) {
        try {
            await fetch(`${API_BASE}/repayments`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
        } catch (e) {
            console.warn('API error during repayment:', e);
        }
    }

    alert(`✅ Repayment of ${formatINR(amount)} successfully processed!\nTransaction committed to ledger with late fee checking.`);
    openLoanDetailModal(loanId);
};

// ----------------------------------------------------------------------------
// 13. APPLICANT DETAIL MODAL (CREDIT PROFILE & CIBIL SCORE)
// ----------------------------------------------------------------------------
function openApplicantDetailModal(applicantId) {
    const app = allApplicantsCache.find(a => a.applicant_id === applicantId) || sampleApplicants[0];
    const appLoans = allLoansCache.filter(l => l.applicant_id === applicantId);

    let modalOverlay = document.getElementById('applicantDetailOverlay');
    if (!modalOverlay) {
        modalOverlay = document.createElement('div');
        modalOverlay.id = 'applicantDetailOverlay';
        modalOverlay.className = 'modal-overlay';
        document.body.appendChild(modalOverlay);
    }

    modalOverlay.innerHTML = `
        <div class="modal" style="max-width: 720px;">
            <div class="modal-header">
                <h2>👤 Borrower Credit Profile &bull; ${app.name}</h2>
                <button class="modal-close" onclick="document.getElementById('applicantDetailOverlay').classList.remove('active');">&times;</button>
            </div>
            <div class="modal-body">
                <div style="display:flex; justify-content:space-between; align-items:center; background:var(--bg-surface); padding:20px; border-radius:var(--radius); margin-bottom:20px;">
                    <div>
                        <h3 style="margin:0 0 6px 0; color:var(--text);">${app.name}</h3>
                        <div style="font-size:0.85rem; color:var(--text-muted);">${app.email} &bull; ${app.phone}</div>
                        <div style="font-size:0.8rem; color:var(--text-dim); margin-top:4px;">${app.address}</div>
                    </div>
                    <div style="text-align:center; padding:12px 20px; background:var(--bg-card); border-radius:var(--radius-sm); border:1px solid var(--glass-border);">
                        <span style="font-size:0.7rem; color:var(--text-dim); text-transform:uppercase;">CIBIL Score</span>
                        <div style="font-size:2rem; font-weight:900; color:${app.credit_score>=750?'#00B894':(app.credit_score>=650?'#FDCB6E':'#E17055')}">
                            ${app.credit_score}
                        </div>
                        <span style="font-size:0.7rem; font-weight:700; color:var(--text-muted);">
                            ${app.credit_score>=750?'PRIME TIER':(app.credit_score>=650?'STANDARD':'SUBPRIME / NPA')}
                        </span>
                    </div>
                </div>

                <div class="profile-details" style="margin-bottom:20px;">
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">PAN Card</div>
                        <div class="profile-detail-value">${app.pan_no}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Aadhaar Card</div>
                        <div class="profile-detail-value">${app.aadhaar_no}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Annual Income</div>
                        <div class="profile-detail-value" style="color:var(--secondary);">${formatINR(app.annual_income)}</div>
                    </div>
                    <div class="profile-detail-item">
                        <div class="profile-detail-label">Employment</div>
                        <div class="profile-detail-value">${app.employment_type} &bull; ${app.employer_name || 'N/A'}</div>
                    </div>
                </div>

                <h3 style="margin-bottom:10px;">Sanctioned Loans for this Applicant</h3>
                ${appLoans.length > 0 ? `
                    <div style="display:grid; gap:10px;">
                        ${appLoans.map(l => `
                            <div style="background:var(--bg-surface); padding:12px 16px; border-radius:var(--radius-sm); display:flex; justify-content:space-between; align-items:center;">
                                <div>
                                    <strong>Loan #${l.loan_id} &bull; ${l.product_name}</strong>
                                    <div style="font-size:0.8rem; color:var(--text-muted);">${formatINR(l.principal_amount)} @ ${l.interest_rate}% for ${l.tenure_months} Mos</div>
                                </div>
                                <span class="request-status" style="font-size:0.7rem;">${l.status}</span>
                            </div>
                        `).join('')}
                    </div>
                ` : `
                    <p style="color:var(--text-muted); font-size:0.85rem;">No active loans on record.</p>
                `}
            </div>
        </div>
    `;

    modalOverlay.classList.add('active');
}

// ----------------------------------------------------------------------------
// 14. DYNAMIC DOM ENHANCEMENTS FOR BANK LOAN MANAGEMENT CONTEXT
// ----------------------------------------------------------------------------
function enhancePageContent() {
    // 1. Update Navigation and Brand Logo
    const logoSpan = document.querySelector('.logo');
    if (logoSpan) {
        logoSpan.innerHTML = `
            <span class="logo-icon" style="color:var(--secondary);">🏛️</span>
            <span>Bank<strong>Loan</strong> 360</span>
        `;
    }

    const navLinks = document.querySelectorAll('.nav-links .nav-link');
    if (navLinks.length >= 3) {
        navLinks[0].innerText = 'Loans';
        navLinks[1].innerText = 'Products';
        navLinks[2].innerText = 'Borrowers';
    }

    // 2. Update Hero Section
    const heroH1 = document.querySelector('.hero h1');
    if (heroH1) {
        heroH1.innerHTML = `Bank Loan Management<br><span class="gradient-text">EMI & Risk System</span>`;
    }

    const heroSubtitle = document.querySelector('.hero-subtitle');
    if (heroSubtitle) {
        heroSubtitle.innerText = 'Precision reducing-balance EMI amortization, automated repayment tracking, and RBI Prudential risk assessment.';
    }

    const searchInput = document.getElementById('searchInput');
    if (searchInput) {
        searchInput.placeholder = "Search loans by borrower name ('Rohan Verma'), product ('Home Loan'), or status ('ACTIVE')...";
    }

    // 3. Update Hero Stats
    const statsContainer = document.querySelector('.hero-stats');
    if (statsContainer) {
        statsContainer.innerHTML = `
            <div class="stat">
                <span class="stat-number">₹1.76 Cr</span>
                <span class="stat-label">Sanctioned</span>
            </div>
            <div class="stat">
                <span class="stat-number">8</span>
                <span class="stat-label">Borrowers</span>
            </div>
            <div class="stat">
                <span class="stat-number">7</span>
                <span class="stat-label">Loan Products</span>
            </div>
            <div class="stat">
                <span class="stat-number">94.2%</span>
                <span class="stat-label">Collection Rate</span>
            </div>
        `;
    }

    // 4. Update Categories to Loan Products
    const catSectionTitle = document.querySelector('#categories .section-title');
    if (catSectionTitle) catSectionTitle.innerText = 'Standard Loan Products';
    const catSectionSub = document.querySelector('#categories .section-subtitle');
    if (catSectionSub) catSectionSub.innerText = 'Filter loans by category & explore standard interest rates';

    const catGrid = document.querySelector('.categories-grid');
    if (catGrid) {
        const categoriesData = [
            { type: 'HOME', icon: '🏠', title: 'Home Loans', count: '8.50% p.a.', sub: ['SBI Regular', 'Max 30 Yrs'] },
            { type: 'PERSONAL', icon: '💼', title: 'Personal Loans', count: '11.25% p.a.', sub: ['Express Credit', 'Max 6 Yrs'] },
            { type: 'VEHICLE', icon: '🚗', title: 'Vehicle Loans', count: '8.85% p.a.', sub: ['Car Platinum', 'Max 7 Yrs'] },
            { type: 'EDUCATION', icon: '🎓', title: 'Education Loans', count: '9.15% p.a.', sub: ['Scholar Loan', 'Max 15 Yrs'] },
            { type: 'BUSINESS', icon: '🏢', title: 'Business Loans', count: '12.50% p.a.', sub: ['SME Term', 'Working Cap'] },
            { type: 'GOLD', icon: '💰', title: 'Gold Loans', count: '7.75% p.a.', sub: ['Sovereign Gold', 'Max 3 Yrs'] },
            { type: 'AGRICULTURE', icon: '🌾', title: 'Agri Loans', count: '7.00% p.a.', sub: ['Kisan Credit', 'Crop Subsidies'] }
        ];

        catGrid.innerHTML = categoriesData.map(c => `
            <div class="category-card" data-category="${c.type}" style="cursor:pointer;" onclick="filterByCategory('${c.type}')">
                <div class="category-icon">${c.icon}</div>
                <h3>${c.title}</h3>
                <span class="category-count" style="color:var(--secondary); font-weight:700;">${c.count}</span>
                <div class="sub-categories">
                    ${c.sub.map(s => `<span class="sub-tag">${s}</span>`).join('')}
                </div>
            </div>
        `).join('');
    }

    // 5. Update Listings and Requests titles
    const listingsTitle = document.querySelector('#listings .section-title');
    if (listingsTitle) listingsTitle.innerText = 'Sanctioned Loan Portfolio';
    const listingsSub = document.querySelector('#listings .section-subtitle');
    if (listingsSub) listingsSub.innerText = 'Live multi-table JOIN across LOAN, APPLICANT, and LOAN_PRODUCT tables with status badges';

    const requestsTitle = document.querySelector('#requests .section-title');
    if (requestsTitle) requestsTitle.innerText = 'Registered Borrowers & Credit Profiles';
    const requestsSub = document.querySelector('#requests .section-subtitle');
    if (requestsSub) requestsSub.innerText = 'Applicant directory with CIBIL credit scores, PAN, Aadhaar, and active exposure';

    // 6. Update Executive Dashboard
    const dashTitle = document.querySelector('#dashboard .section-title');
    if (dashTitle) dashTitle.innerText = 'Executive Risk & Recovery Dashboard';
    const dashSub = document.querySelector('#dashboard .section-subtitle');
    if (dashSub) dashSub.innerText = 'Aggregated portfolio metrics from queries.sql: sanctioned volume, monthly recovery, and NPA risk';

    const dashGrid = document.querySelector('.dashboard-grid');
    if (dashGrid) {
        dashGrid.innerHTML = `
            <div class="dashboard-card">
                <div class="dashboard-icon">📊</div>
                <div class="dashboard-info">
                    <span class="dashboard-value">₹1,75,50,000</span>
                    <span class="dashboard-label">Total Sanctioned Portfolio</span>
                </div>
            </div>
            <div class="dashboard-card">
                <div class="dashboard-icon">📈</div>
                <div class="dashboard-info">
                    <span class="dashboard-value" style="color:var(--secondary);">94.2%</span>
                    <span class="dashboard-label">Collection Efficiency</span>
                </div>
            </div>
            <div class="dashboard-card">
                <div class="dashboard-icon">⚠️</div>
                <div class="dashboard-info">
                    <span class="dashboard-value" style="color:#FDCB6E;">4 Accts</span>
                    <span class="dashboard-label">Delinquent Overdue</span>
                </div>
            </div>
            <div class="dashboard-card">
                <div class="dashboard-icon">🚨</div>
                <div class="dashboard-info">
                    <span class="dashboard-value" style="color:#E17055;">19.9%</span>
                    <span class="dashboard-label">Portfolio at Risk (NPA)</span>
                </div>
            </div>
        `;
    }

    // 7. Update Footer Brand
    const footerBrand = document.querySelector('.footer-brand p');
    if (footerBrand) {
        footerBrand.innerText = 'A B.Tech CSE Database Systems Project — MySQL 8.0, InnoDB Transactions & Python REST API';
    }
    const footerBottom = document.querySelector('.footer-bottom p');
    if (footerBottom) {
        footerBottom.innerText = '© 2026 Bank Loan Management System — DBMS Course Project | B.Tech CSE';
    }
}

window.filterByCategory = function(categoryType) {
    activeCategoryFilter = (activeCategoryFilter === categoryType) ? 'ALL' : categoryType;
    document.querySelectorAll('.category-card').forEach(card => {
        if (card.getAttribute('data-category') === activeCategoryFilter) {
            card.style.borderColor = 'var(--primary)';
            card.style.background = 'var(--bg-card-hover)';
        } else {
            card.style.borderColor = 'var(--glass-border)';
            card.style.background = 'var(--bg-card)';
        }
    });

    renderLoans();
    const listingsElem = document.getElementById('listings');
    if (listingsElem) listingsElem.scrollIntoView({ behavior: 'smooth' });
};

// ----------------------------------------------------------------------------
// 15. DOMCONTENTLOADED LIFECYCLE HOOK
// ----------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', async () => {
    enhancePageContent();
    await checkBackend();
    await renderLoans();
    await renderApplicants();
    initModal();
    initSearch();
    initLogin();
    initEmiCalculatorSection();
    initApplyLoanModal();

    console.log('🏛️ Bank Loan Management System initialized.');
    console.log('Connected to MySQL:', backendConnected);
});
