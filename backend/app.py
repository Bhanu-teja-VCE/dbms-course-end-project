# ============================================================================
# CampusSwap — Flask Backend
# Connects the frontend to the MySQL database.
# Every endpoint runs REAL SQL queries — the same ones from queries.sql.
#
# Run:   pip install -r requirements.txt
#        python app.py
# Visit: http://localhost:5000
# ============================================================================

import os
import json
from datetime import datetime, date
from decimal import Decimal
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error

# ---- APP SETUP ----
app = Flask(__name__,
            static_folder=os.path.join(os.path.dirname(__file__), '..', 'frontend'),
            static_url_path='')
CORS(app)  # Allow frontend to call API during development

# ---- DATABASE CONFIG ----
# Change these if your MySQL credentials are different
DB_CONFIG = {
    'host':     os.environ.get('DB_HOST', 'localhost'),
    'user':     os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),      # <-- set your MySQL password here or via env var
    'database': 'campusswap',
    'charset':  'utf8mb4',
    'autocommit': True,
}


def get_db():
    """Create a fresh database connection.
    
    VIVA NOTE: We create a new connection per request instead of reusing one
    because MySQL connections aren't thread-safe. In production you'd use
    a connection pool, but for a course project this is simpler.
    """
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        return conn
    except Error as e:
        print(f"Database connection failed: {e}")
        return None


def query_db(sql, params=None, fetchone=False):
    """Execute a SELECT query and return results as list of dicts.
    
    This helper converts each row into a dictionary using column names,
    which makes it easy to return as JSON.
    """
    conn = get_db()
    if not conn:
        return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(sql, params or ())
        result = cursor.fetchone() if fetchone else cursor.fetchall()
        return result
    except Error as e:
        print(f"Query error: {e}")
        return None
    finally:
        conn.close()


def execute_db(sql, params=None):
    """Execute an INSERT/UPDATE/DELETE and return affected rows + last ID."""
    conn = get_db()
    if not conn:
        return None, None
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params or ())
        conn.commit()
        return cursor.lastrowid, cursor.rowcount
    except Error as e:
        print(f"Execute error: {e}")
        conn.rollback()
        return None, None
    finally:
        conn.close()


def call_procedure(proc_name, params=None):
    """Call a stored procedure and return its result set."""
    conn = get_db()
    if not conn:
        return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.callproc(proc_name, params or ())
        # Stored procedures can return multiple result sets
        results = []
        for result in cursor.stored_results():
            results.extend(result.fetchall())
        conn.commit()
        return results
    except Error as e:
        print(f"Procedure error: {e}")
        conn.rollback()
        return None
    finally:
        conn.close()


def serialize(obj):
    """JSON serializer for types not handled by default (Decimal, datetime)."""
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


# Patch Flask's jsonify to handle Decimal and datetime
app.json.default = serialize


# ============================================================================
# STATIC FILE SERVING — serves the frontend
# ============================================================================

@app.route('/')
def serve_frontend():
    """Serve index.html — the marketplace UI."""
    return send_from_directory(app.static_folder, 'index.html')


# ============================================================================
# API ENDPOINTS — each one runs a real SQL query
# ============================================================================

# --------------- USERS & AUTH ---------------

@app.route('/api/users')
def get_users():
    """
    GET /api/users
    Returns all registered users with their seller/buyer status.
    
    SQL: SELECT u.*, s.seller_id IS NOT NULL, b.buyer_id IS NOT NULL
         FROM `USER` u LEFT JOIN SELLER s ... LEFT JOIN BUYER b ...
    """
    sql = """
        SELECT u.user_id, u.name, u.email, u.phone,
               u.hostel_block, u.room_no, u.joined_at,
               s.seller_id IS NOT NULL AS is_seller,
               b.buyer_id IS NOT NULL  AS is_buyer,
               s.upi_id, IFNULL(s.total_sales, 0) AS total_sales,
               IFNULL(s.avg_rating, 0) AS avg_rating,
               IFNULL(b.wallet_balance, 0) AS wallet_balance
        FROM `USER` u
        LEFT JOIN SELLER s ON u.user_id = s.seller_id
        LEFT JOIN BUYER b  ON u.user_id = b.buyer_id
        ORDER BY u.user_id
        LIMIT 20
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected', 'users': []}), 503

    # Convert tinyint booleans
    for r in rows:
        r['is_seller'] = bool(r['is_seller'])
        r['is_buyer'] = bool(r['is_buyer'])

    return jsonify({
        'users': rows,
        'sql': sql.strip(),
        'viva': 'LEFT JOIN ensures users without seller/buyer entries still appear.'
    })


@app.route('/api/users/<int:user_id>')
def get_user_profile(user_id):
    """
    GET /api/users/:id
    Detailed profile for one user — joins USER, SELLER, BUYER, counts listings & orders.
    This is the seller_dashboard_view query applied to one user.
    """
    sql = """
        SELECT u.user_id, u.name, u.email, u.phone,
               u.hostel_block, u.room_no, u.joined_at,
               s.seller_id IS NOT NULL AS is_seller,
               b.buyer_id IS NOT NULL  AS is_buyer,
               s.upi_id,
               IFNULL(s.total_sales, 0) AS total_sales,
               IFNULL(s.avg_rating, 0)  AS avg_rating,
               IFNULL(b.wallet_balance, 0) AS wallet_balance,
               (SELECT COUNT(*) FROM LISTING l WHERE l.seller_id = u.user_id) AS listing_count,
               (SELECT COUNT(*) FROM LISTING l WHERE l.seller_id = u.user_id AND l.status = 'ACTIVE') AS active_listings,
               (SELECT COUNT(*) FROM ORDERS o WHERE o.buyer_id = u.user_id) AS order_count
        FROM `USER` u
        LEFT JOIN SELLER s ON u.user_id = s.seller_id
        LEFT JOIN BUYER b  ON u.user_id = b.buyer_id
        WHERE u.user_id = %s
    """
    row = query_db(sql, (user_id,), fetchone=True)
    if not row:
        return jsonify({'error': 'User not found'}), 404

    row['is_seller'] = bool(row['is_seller'])
    row['is_buyer'] = bool(row['is_buyer'])

    return jsonify({
        'user': row,
        'sql': sql.strip().replace('%s', str(user_id)),
        'viva': 'Scalar subqueries count listings/orders for this user. LEFT JOINs handle users who are not sellers or buyers.'
    })


# --------------- LISTINGS ---------------

@app.route('/api/listings')
def get_listings():
    """
    GET /api/listings?category_id=3&status=ACTIVE&search=data
    Fetches listings — this is the available_listings_view brought to life.
    Supports filtering by category, status, and title search.
    """
    conditions = []
    params = []

    # Optional filters
    category_id = request.args.get('category_id')
    status = request.args.get('status', 'ACTIVE')
    search = request.args.get('search')

    base_sql = """
        SELECT l.listing_id, l.title, l.description, l.price, l.quantity,
               l.`condition`, l.status, l.image_url, l.created_at,
               c.name AS category_name, c.category_id,
               u.name AS seller_name, u.hostel_block AS seller_hostel,
               s.avg_rating AS seller_rating,
               bd.isbn, bd.author, bd.edition, bd.subject
        FROM LISTING l
        JOIN CATEGORY c ON l.category_id = c.category_id
        JOIN SELLER s   ON l.seller_id = s.seller_id
        JOIN `USER` u   ON s.seller_id = u.user_id
        LEFT JOIN BOOK_DETAILS bd ON l.listing_id = bd.listing_id
    """

    if status:
        conditions.append("l.status = %s")
        params.append(status)
    if category_id:
        conditions.append("l.category_id = %s")
        params.append(int(category_id))
    if search:
        conditions.append("l.title LIKE %s")
        params.append(f"%{search}%")

    if conditions:
        base_sql += " WHERE " + " AND ".join(conditions)

    base_sql += " ORDER BY l.created_at DESC LIMIT 50"

    rows = query_db(base_sql, params)
    if rows is None:
        return jsonify({'error': 'Database not connected', 'listings': []}), 503

    return jsonify({
        'listings': rows,
        'count': len(rows),
        'sql': base_sql.strip(),
        'viva': 'This is the available_listings_view with dynamic WHERE filters. LEFT JOIN on BOOK_DETAILS because not every listing is a book.'
    })


@app.route('/api/listings', methods=['POST'])
def create_listing():
    """
    POST /api/listings
    Creates a new listing. Demonstrates:
    1. Overlapping specialization: Creates SELLER record if user isn't a seller yet.
    2. BOOK_DETAILS specialization: Inserts into child table if item is a book.
    3. Constraints enforced: CHECK (price > 0), CHECK (quantity >= 0).
    """
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    seller_id = data.get('seller_id')
    category_id = data.get('category_id', 1)
    title = data.get('title', '').strip()
    description = data.get('description', '')
    price = data.get('price')
    quantity = data.get('quantity', 1)
    condition = data.get('condition', 'GOOD')
    is_book = data.get('is_book', False)
    author = data.get('author')
    isbn = data.get('isbn')

    if not seller_id or not title or price is None:
        return jsonify({'error': 'seller_id, title, and price are required'}), 400

    # Ensure user is a SELLER (Overlapping specialization rule)
    execute_db(
        "INSERT IGNORE INTO SELLER (seller_id, upi_id) VALUES (%s, %s)",
        (seller_id, f"student{seller_id}@upi")
    )

    insert_sql = """
        INSERT INTO LISTING (seller_id, category_id, title, description, price, quantity, `condition`, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, 'ACTIVE')
    """
    listing_id, rowcount = execute_db(
        insert_sql,
        (seller_id, category_id, title, description, price, quantity, condition)
    )

    if not listing_id:
        return jsonify({'error': 'Failed to insert listing (check constraints like price > 0)'}), 400

    if is_book and listing_id:
        execute_db(
            "INSERT INTO BOOK_DETAILS (listing_id, isbn, author) VALUES (%s, %s, %s)",
            (listing_id, isbn or 'N/A', author or 'Unknown')
        )

    return jsonify({
        'status': 'success',
        'listing_id': listing_id,
        'sql': f"INSERT INTO LISTING (seller_id, category_id, title, price, quantity, condition) VALUES ({seller_id}, {category_id}, '{title}', {price}, {quantity}, '{condition}');",
        'viva': 'Demonstrates ER specialization insertion: SELLER record created if needed, and optional BOOK_DETAILS record created for book subtypes.'
    }), 201


# --------------- CATEGORIES ---------------

@app.route('/api/categories')
def get_categories():
    """
    GET /api/categories
    Returns categories with parent info and listing counts.
    Shows the self-referencing FK in action.
    """
    sql = """
        SELECT c.category_id, c.name, c.parent_category_id,
               p.name AS parent_name,
               COUNT(l.listing_id) AS listing_count
        FROM CATEGORY c
        LEFT JOIN CATEGORY p ON c.parent_category_id = p.category_id
        LEFT JOIN LISTING l  ON c.category_id = l.category_id AND l.status = 'ACTIVE'
        GROUP BY c.category_id, c.name, c.parent_category_id, p.name
        ORDER BY c.parent_category_id IS NULL DESC, c.parent_category_id, c.name
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected', 'categories': []}), 503

    return jsonify({
        'categories': rows,
        'sql': sql.strip(),
        'viva': 'Self-referencing FK: p.name is the parent category. NULL parent = top-level.'
    })


# --------------- REQUESTS ---------------

@app.route('/api/requests')
def get_requests():
    """
    GET /api/requests
    Returns wanted-requests from students.
    """
    sql = """
        SELECT r.request_id, r.title, r.description, r.budget_max,
               r.status, r.created_at,
               u.name AS user_name, u.hostel_block,
               c.name AS category_name
        FROM REQUEST r
        JOIN `USER` u ON r.user_id = u.user_id
        LEFT JOIN CATEGORY c ON r.category_id = c.category_id
        ORDER BY r.created_at DESC
        LIMIT 20
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected', 'requests': []}), 503

    return jsonify({'requests': rows, 'sql': sql.strip()})


# --------------- REVIEWS ---------------

@app.route('/api/listings/<int:listing_id>/reviews')
def get_reviews(listing_id):
    """
    GET /api/listings/:id/reviews
    Returns reviews for a specific listing.
    """
    sql = """
        SELECT r.review_id, r.rating, r.comment, r.created_at,
               u.name AS reviewer_name
        FROM REVIEW r
        JOIN `USER` u ON r.reviewer_id = u.user_id
        WHERE r.listing_id = %s
        ORDER BY r.created_at DESC
    """
    rows = query_db(sql, (listing_id,))
    if rows is None:
        return jsonify({'error': 'Database not connected', 'reviews': []}), 503

    return jsonify({'reviews': rows, 'sql': sql.strip()})


# --------------- ORDERS (calls the stored procedure!) ---------------

@app.route('/api/orders', methods=['POST'])
def place_order():
    """
    POST /api/orders
    Body: { "buyer_id": 1, "listing_id": 5, "quantity": 1, "method": "UPI" }
    
    Calls the place_order stored procedure — an ACID transaction!
    """
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    buyer_id = data.get('buyer_id')
    listing_id = data.get('listing_id')
    qty = data.get('quantity', 1)
    method = data.get('method', 'UPI')

    if not buyer_id or not listing_id:
        return jsonify({'error': 'buyer_id and listing_id are required'}), 400

    result = call_procedure('place_order', (buyer_id, listing_id, qty, method))

    if result is None:
        return jsonify({'error': 'Order failed — check database connection'}), 500

    return jsonify({
        'result': result,
        'sql': f"CALL place_order({buyer_id}, {listing_id}, {qty}, '{method}');",
        'viva': 'This calls the ACID stored procedure. START TRANSACTION → check stock → INSERT order → UPDATE quantity → INSERT payment → COMMIT. Rolls back on any error.'
    })


# --------------- ANALYTICS QUERIES (from queries.sql) ---------------

@app.route('/api/analytics/top-sellers')
def top_sellers():
    """
    Query 1: Top 5 sellers by revenue
    """
    sql = """
        SELECT u.name AS seller_name,
               SUM(oi.price_at_purchase * oi.quantity) AS total_revenue
        FROM `USER` u
        JOIN SELLER s ON u.user_id = s.seller_id
        JOIN LISTING l ON s.seller_id = l.seller_id
        JOIN ORDER_ITEM oi ON l.listing_id = oi.listing_id
        GROUP BY s.seller_id, u.name
        ORDER BY total_revenue DESC
        LIMIT 5
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Top 5 Sellers by Revenue',
        'concepts': 'Multi-table JOIN, GROUP BY, aggregate SUM, ORDER BY DESC, LIMIT'
    })


@app.route('/api/analytics/popular-categories')
def popular_categories():
    """
    Query 2: Categories with more than 10 listings (HAVING)
    """
    sql = """
        SELECT c.name AS category_name,
               COUNT(l.listing_id) AS listing_count
        FROM CATEGORY c
        JOIN LISTING l ON c.category_id = l.category_id
        GROUP BY c.category_id, c.name
        HAVING COUNT(l.listing_id) > 10
        ORDER BY listing_count DESC
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Categories with 10+ Listings',
        'concepts': 'GROUP BY with HAVING — filters AFTER aggregation (unlike WHERE which filters BEFORE)'
    })


@app.route('/api/analytics/below-average')
def below_average():
    """
    Query 3: Listings priced below their category average (correlated subquery)
    """
    sql = """
        SELECT l.title, l.price, c.name AS category_name,
               (SELECT ROUND(AVG(l2.price), 2) FROM LISTING l2
                WHERE l2.category_id = l.category_id) AS category_avg
        FROM LISTING l
        JOIN CATEGORY c ON l.category_id = c.category_id
        WHERE l.price < (
            SELECT AVG(l2.price) FROM LISTING l2
            WHERE l2.category_id = l.category_id
        )
        AND l.status = 'ACTIVE'
        ORDER BY c.name, l.price
        LIMIT 20
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Listings Below Category Average',
        'concepts': 'Correlated subquery — inner query references outer query\'s l.category_id, re-executes per row'
    })


@app.route('/api/analytics/users-no-orders')
def users_no_orders():
    """
    Query 4: Users with no orders (LEFT JOIN + IS NULL)
    """
    sql = """
        SELECT u.name, u.email, u.hostel_block
        FROM `USER` u
        LEFT JOIN BUYER b ON u.user_id = b.buyer_id
        LEFT JOIN ORDERS o ON b.buyer_id = o.buyer_id
        WHERE o.order_id IS NULL
        ORDER BY u.name
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Users With No Orders',
        'concepts': 'LEFT JOIN keeps all left rows. IS NULL on right side finds "missing" matches.'
    })


@app.route('/api/analytics/most-requested')
def most_requested():
    """
    Query 5: Most requested categories
    """
    sql = """
        SELECT c.name AS category_name,
               COUNT(r.request_id) AS request_count
        FROM REQUEST r
        JOIN CATEGORY c ON r.category_id = c.category_id
        GROUP BY c.category_id, c.name
        ORDER BY request_count DESC
        LIMIT 10
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Most Requested Categories',
        'concepts': 'Simple GROUP BY with COUNT aggregate, sorted by popularity'
    })


@app.route('/api/analytics/set-operators')
def set_operators():
    """
    Queries 6, 7, 8: UNION, INTERSECT equivalent, EXCEPT equivalent
    """
    union_sql = """
        SELECT u.user_id, u.name, 'Seller' AS role
        FROM `USER` u JOIN SELLER s ON u.user_id = s.seller_id
        UNION
        SELECT u.user_id, u.name, 'Requester' AS role
        FROM `USER` u JOIN REQUEST r ON u.user_id = r.user_id
    """

    intersect_sql = """
        SELECT u.user_id, u.name
        FROM `USER` u
        JOIN SELLER s ON u.user_id = s.seller_id
        JOIN BUYER b  ON u.user_id = b.buyer_id
    """

    except_sql = """
        SELECT u.user_id, u.name
        FROM `USER` u
        JOIN SELLER s ON u.user_id = s.seller_id
        LEFT JOIN LISTING l ON s.seller_id = l.seller_id
        LEFT JOIN REVIEW r  ON l.listing_id = r.listing_id
        WHERE r.review_id IS NULL
    """

    union_rows = query_db(union_sql)
    intersect_rows = query_db(intersect_sql)
    except_rows = query_db(except_sql)

    return jsonify({
        'union': {
            'data': union_rows or [],
            'sql': union_sql.strip(),
            'name': 'UNION — Sellers OR Requesters',
            'note': 'UNION removes duplicates. UNION ALL keeps them.'
        },
        'intersect': {
            'data': intersect_rows or [],
            'sql': intersect_sql.strip(),
            'name': 'INTERSECT equivalent — Both Seller AND Buyer',
            'note': 'MySQL lacks INTERSECT. We use INNER JOIN instead. Oracle: SELECT ... INTERSECT SELECT ...'
        },
        'except': {
            'data': except_rows or [],
            'sql': except_sql.strip(),
            'name': 'EXCEPT equivalent — Sellers Never Reviewed',
            'note': 'MySQL lacks EXCEPT. We use LEFT JOIN + IS NULL. Oracle: SELECT ... MINUS SELECT ...'
        }
    })


@app.route('/api/analytics/revenue-by-month')
def revenue_by_month():
    """
    Query 9: Revenue by month
    """
    sql = """
        SELECT DATE_FORMAT(o.order_date, '%%Y-%%m') AS month,
               SUM(o.total_amount) AS revenue,
               COUNT(o.order_id) AS order_count
        FROM ORDERS o
        WHERE o.status IN ('CONFIRMED', 'DELIVERED')
        GROUP BY DATE_FORMAT(o.order_date, '%%Y-%%m')
        ORDER BY month DESC
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip().replace('%%', '%'),
        'query_name': 'Revenue by Month',
        'concepts': 'DATE_FORMAT extracts year-month. GROUP BY month for time-series aggregation.'
    })


@app.route('/api/analytics/top-rated')
def top_rated():
    """
    Query 10: Top-rated listings with minimum 3 reviews
    """
    sql = """
        SELECT l.title, l.price,
               ROUND(AVG(r.rating), 1) AS avg_rating,
               COUNT(r.review_id) AS review_count,
               u.name AS seller_name
        FROM LISTING l
        JOIN REVIEW r ON l.listing_id = r.listing_id
        JOIN SELLER s ON l.seller_id = s.seller_id
        JOIN `USER` u ON s.seller_id = u.user_id
        GROUP BY l.listing_id, l.title, l.price, u.name
        HAVING COUNT(r.review_id) >= 3
        ORDER BY avg_rating DESC, review_count DESC
        LIMIT 10
    """
    rows = query_db(sql)
    if rows is None:
        return jsonify({'error': 'Database not connected'}), 503

    return jsonify({
        'data': rows,
        'sql': sql.strip(),
        'query_name': 'Top-Rated Listings (min 3 reviews)',
        'concepts': 'HAVING with COUNT filter after GROUP BY. AVG for mean rating.'
    })


# --------------- SELLER REPORT (calls stored procedure) ---------------

@app.route('/api/sellers/<int:seller_id>/report')
def seller_report(seller_id):
    """
    Calls get_seller_report stored procedure.
    """
    result = call_procedure('get_seller_report', (seller_id,))
    if result is None:
        return jsonify({'error': 'Procedure failed'}), 500

    return jsonify({
        'report': result,
        'sql': f"CALL get_seller_report({seller_id});",
        'viva': 'Stored procedure encapsulates a complex multi-JOIN query so the application just calls one name.'
    })


# --------------- HEALTH CHECK ---------------

@app.route('/api/health')
def health():
    """Check if the database is reachable."""
    conn = get_db()
    if conn:
        conn.close()
        return jsonify({'status': 'ok', 'database': 'connected'})
    return jsonify({'status': 'error', 'database': 'disconnected'}), 503


# ============================================================================
# MAIN
# ============================================================================
if __name__ == '__main__':
    print("=" * 60)
    print("  CampusSwap Backend Server")
    print("  http://localhost:5000")
    print("  API:       http://localhost:5000/api/health")
    print("  Frontend:  http://localhost:5000")
    print("=" * 60)
    print()
    print("  Make sure MySQL is running and campusswap DB is loaded:")
    print("    mysql -u root -p < sql/schema.sql")
    print("    mysql -u root -p < sql/seed.sql")
    print()

    # Check DB connection on startup
    conn = get_db()
    if conn:
        print("  ✓ Database connected successfully!")
        conn.close()
    else:
        print("  ✗ Database connection FAILED.")
        print("    Set DB_PASSWORD env var or edit DB_CONFIG in app.py")
    print("=" * 60)

    app.run(debug=True, port=5000)
