from flask import Flask, jsonify, request, render_template, redirect, url_for, flash
import mysql.connector
from mysql.connector import Error
import bcrypt

app = Flask(__name__)
app.secret_key = "super_secret_key_for_session"


# ─────────────────────────────────────────────
# DB CONNECTIONS
# ─────────────────────────────────────────────
def get_db_connection():
    return mysql.connector.connect(
        host="localhost", user="root",
        password="Vansh173@", database="supplychain_db"
    )

def get_auth_connection():
    return mysql.connector.connect(
        host="localhost", user="root",
        password="Vansh173@", database="auth_db"
    )


# =========================================================
# BASIC / HEALTH ROUTES
# =========================================================
@app.route("/")
def home():
    return redirect(url_for("login_page"))

@app.route("/health")
def health():
    try:
        conn = get_db_connection()
        if conn.is_connected():
            conn.close()
            return "DB connected", 200
    except Error:
        return "DB not connected", 500


# =========================================================
# AUTH PAGES
# =========================================================
@app.route("/login")
def login_page():
    return render_template("auth/login.html")

@app.route("/signup-page")
def signup_page():
    return render_template("auth/signup.html")


# =========================================================
# AUTH API ROUTES
# =========================================================
@app.route("/signup", methods=["POST"])
def signup():
    auth_conn = None
    db_conn   = None
    try:
        data     = request.json
        username = data["username"]
        password = data["password"]
        role_id  = int(data["role_id"])

        if len(password) < 6:
            return {"error": "Password must be at least 6 characters."}, 400

        hashed    = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
        linked_id = None

        db_conn = get_db_connection()
        db_cur  = db_conn.cursor()

        # ── PRODUCER: create Producer row ────────────────────────────
        if role_id == 1:
            company_name = data.get("company_name", "").strip()
            phone        = data.get("phone", "").strip()
            email        = data.get("email", "").strip()
            if not company_name:
                return {"error": "Company name is required."}, 400
            if not phone:
                return {"error": "Phone number is required."}, 400
            if not email:
                return {"error": "Email is required."}, 400

            db_conn.start_transaction()
            db_cur.execute(
                """INSERT INTO Producer (producer_name, phone, email, approval_status, earnings)
                   VALUES (%s, %s, %s, 'Approved', 0.00)""",
                (company_name, phone, email)
            )
            linked_id = db_cur.lastrowid
            db_conn.commit()

        # ── ADMIN: always link to warehouse_id = 1 (Main Warehouse) ──
        elif role_id == 2:
            # Make sure warehouse 1 exists
            db_cur.execute("SELECT warehouse_id FROM Warehouse WHERE warehouse_id = 1")
            wh = db_cur.fetchone()
            if not wh:
                return {"error": "Main Warehouse (id=1) not found. Run data.sql first."}, 400
            linked_id = 1

        # ── CUSTOMER: create Customer row + Wallet ───────────────────
        elif role_id == 3:
            first_name = data.get("first_name", "").strip()
            last_name  = data.get("last_name", "").strip()
            if not first_name or not last_name:
                return {"error": "First and last name are required for customers."}, 400

            db_conn.start_transaction()
            db_cur.execute(
                "INSERT INTO Customer (first_name, last_name, email) VALUES (%s, %s, %s)",
                (first_name, last_name, f"{username}@kiranmart.local")
            )
            linked_id = db_cur.lastrowid
            db_cur.execute(
                "INSERT INTO Wallet (customer_id, balance) VALUES (%s, 0.00)",
                (linked_id,)
            )
            db_conn.commit()

        db_cur.close()

        # ── Create auth user with linked_id ──────────────────────────
        auth_conn = get_auth_connection()
        auth_cur  = auth_conn.cursor()
        auth_cur.execute(
            "INSERT INTO users (username, password_hash, role_id, linked_id) VALUES (%s, %s, %s, %s)",
            (username, hashed.decode(), role_id, linked_id)
        )
        auth_conn.commit()
        auth_cur.close()

        return {"message": "User created", "role_id": role_id, "user_id": linked_id}, 201

    except mysql.connector.Error as e:
        if db_conn:
            try: db_conn.rollback()
            except: pass
        if e.errno == 1062:
            return {"error": "Username already exists."}, 409
        return {"error": "Signup failed", "details": str(e)}, 500
    except Exception as e:
        if db_conn:
            try: db_conn.rollback()
            except: pass
        return {"error": str(e)}, 500
    finally:
        if auth_conn: auth_conn.close()
        if db_conn:   db_conn.close()


@app.route("/login", methods=["POST"])
def login():
    conn = None; cursor = None
    try:
        data     = request.json
        username = data["username"]
        password = data["password"]
        conn   = get_auth_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT password_hash, role_id, linked_id FROM users WHERE username = %s",
            (username,)
        )
        user = cursor.fetchone()
        if not user:
            return {"error": "User not found"}, 404
        if not bcrypt.checkpw(password.encode(), user["password_hash"].encode()):
            return {"error": "Invalid password"}, 401
        return {
            "message":  "Login successful",
            "role_id":  user["role_id"],
            "user_id":  user["linked_id"]
        }, 200
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()


# =========================================================
# DASHBOARD REDIRECT TARGETS
# =========================================================
@app.route("/producer")
def producer_redirect():
    return redirect(url_for("producer_dashboard", producer_id=1))

@app.route("/admin")
def admin_redirect():
    return redirect(url_for("warehouse_dashboard", warehouse_id=1))

@app.route("/customer")
def customer_redirect():
    return redirect(url_for("customer_dashboard", customer_id=1))

@app.route("/link-account", methods=["POST"])
def link_account():
    conn = None; cursor = None
    try:
        data      = request.json
        username  = data["username"]
        linked_id = int(data["linked_id"])
        conn   = get_auth_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET linked_id = %s WHERE username = %s", (linked_id, username))
        if cursor.rowcount == 0:
            return {"error": "User not found"}, 404
        conn.commit()
        return {"message": f"Linked {username} → ID {linked_id}"}, 200
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()


# =========================================================
# READ-ONLY DATA ROUTES
# =========================================================
@app.route("/producers")
def get_producers():
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT producer_id, producer_name FROM Producer;")
        producers = cursor.fetchall()
        cursor.close(); conn.close()
        return jsonify(producers), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500

@app.route("/inventory")
def inventory():
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT w.warehouse_name, p.product_name, i.available_qty
            FROM Inventory i
            JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
            JOIN Product   p ON i.product_id   = p.product_id;
        """)
        data = cursor.fetchall()
        cursor.close(); conn.close()
        return jsonify(data), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500

@app.route("/batches")
def batches():
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT b.batch_id, p.product_name, w.warehouse_name,
                   b.quantity, b.unit_cost, b.arrival_date
            FROM Batch b
            JOIN Product   p ON b.product_id   = p.product_id
            JOIN Warehouse w ON b.warehouse_id = w.warehouse_id;
        """)
        data = cursor.fetchall()
        cursor.close(); conn.close()
        return jsonify(data), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500


# =========================================================
# TRANSACTION ROUTES
# =========================================================
@app.route("/place-order", methods=["POST"])
def place_order():
    conn = None; cursor = None
    try:
        data         = request.json
        customer_id  = data["customer_id"]
        warehouse_id = data["warehouse_id"]
        product_id   = data["product_id"]
        quantity     = data["quantity"]
        conn   = get_db_connection()
        cursor = conn.cursor()
        conn.start_transaction()
        cursor.execute(
            "INSERT INTO `Order` (customer_id, warehouse_id, order_status) VALUES (%s, %s, %s)",
            (customer_id, warehouse_id, "CREATED")
        )
        order_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO Order_Item (order_id, product_id, quantity) VALUES (%s, %s, %s)",
            (order_id, product_id, quantity)
        )
        conn.commit()
        return jsonify({"message": "Order placed successfully", "order_id": order_id}), 201
    except Exception as e:
        if conn: conn.rollback()
        return jsonify({"error": "Transaction failed, rolled back", "details": str(e)}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()

@app.route("/confirm-order", methods=["POST"])
def confirm_order():
    try:
        data     = request.json
        order_id = data["order_id"]
        conn   = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE `Order` SET order_status = %s WHERE order_id = %s", ("CONFIRMED", order_id))
        conn.commit(); cursor.close(); conn.close()
        return jsonify({"message": "Order confirmed successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/test-failure", methods=["POST"])
def test_failure():
    conn = None; cursor = None
    try:
        data         = request.json
        customer_id  = data["customer_id"]
        warehouse_id = data["warehouse_id"]
        product_id   = data["product_id"]
        quantity     = data["quantity"]
        conn   = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
        conn.start_transaction()
        cursor.execute(
            "INSERT INTO `Order` (customer_id, warehouse_id, order_status) VALUES (%s, %s, %s)",
            (customer_id, warehouse_id, "CREATED")
        )
        order_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO Order_Item (order_id, product_id, quantity) VALUES (%s, %s, %s)",
            (order_id, product_id, quantity)
        )
        x = 1 / 0
        conn.commit()
        return {"message": "This should never execute"}
    except Exception as e:
        if conn: conn.rollback()
        return {"error": "Forced failure occurred, transaction rolled back", "details": str(e)}, 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()


# =========================================================
# DEMO / ANALYTICS ROUTES
# =========================================================
@app.route("/demo/inventory")
def demo_inventory():
    conn = None; cursor = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT w.warehouse_name, p.product_name, i.available_qty, i.reserved_qty
            FROM Inventory i
            JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
            JOIN Product   p ON i.product_id   = p.product_id;
        """)
        return jsonify(cursor.fetchall()), 200
    except Exception:
        return jsonify({"error": "Unable to fetch inventory data"}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()

@app.route("/demo/orders")
def demo_orders():
    conn = None; cursor = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT o.order_id, c.first_name, c.last_name,
                   w.warehouse_name, o.order_status, o.created_at
            FROM `Order` o
            JOIN Customer  c ON o.customer_id  = c.customer_id
            JOIN Warehouse w ON o.warehouse_id = w.warehouse_id
            ORDER BY o.order_id DESC;
        """)
        return jsonify(cursor.fetchall()), 200
    except Exception as e:
        return jsonify({"error": "Unable to fetch orders", "details": str(e)}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()

@app.route("/demo/wallets")
def demo_wallets():
    conn = None; cursor = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT c.first_name, c.last_name, w.balance
            FROM Wallet w JOIN Customer c ON w.customer_id = c.customer_id;
        """)
        return jsonify(cursor.fetchall()), 200
    except Exception:
        return jsonify({"error": "Unable to fetch wallet data"}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()

@app.route("/analytics/low-stock")
def analytics_low_stock():
    conn = None; cursor = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_low_stock_products;")
        return jsonify(cursor.fetchall()), 200
    except Exception:
        return jsonify({"error": "Unable to fetch low stock analytics"}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()

@app.route("/analytics/warehouse-summary")
def analytics_warehouse_summary():
    conn = None; cursor = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM v_warehouse_summary;")
        return jsonify(cursor.fetchall()), 200
    except Exception:
        return jsonify({"error": "Unable to fetch warehouse summary analytics"}), 500
    finally:
        if cursor: cursor.close()
        if conn:   conn.close()


# =========================================================
# WAREHOUSE / ADMIN ROUTES
# =========================================================
@app.route("/warehouse/<int:warehouse_id>")
def warehouse_dashboard(warehouse_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM Warehouse WHERE warehouse_id = %s", (warehouse_id,))
        warehouse = cursor.fetchone()
        if not warehouse:
            return f"<h2>Warehouse ID {warehouse_id} not found. <a href=/login>Back to Login</a></h2>", 404
        cursor.execute("""
            SELECT pp.producer_id, pr.producer_name, pp.product_id, p.product_name,
                   pp.price_before_tax, pp.max_batch_limit
            FROM Producer_Product pp
            JOIN Producer pr ON pp.producer_id = pr.producer_id
            JOIN Product   p  ON pp.product_id  = p.product_id
            WHERE pr.approval_status = 'Approved'
            ORDER BY pr.producer_name, p.product_name
        """)
        catalogue = cursor.fetchall()
        cursor.execute("""
            SELECT rr.request_id, pr.producer_name, p.product_name,
                   rr.requested_qty, rr.quoted_price, rr.status, rr.created_at,
                   pp.price_before_tax AS current_price
            FROM Restock_Request rr
            JOIN Producer pr ON rr.producer_id = pr.producer_id
            JOIN Product   p  ON rr.product_id  = p.product_id
            JOIN Producer_Product pp
                ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
            WHERE rr.warehouse_id = %s
            ORDER BY rr.created_at DESC LIMIT 20
        """, (warehouse_id,))
        requests_list = cursor.fetchall()
        cursor.execute("""
            SELECT rr.request_id, rr.requested_qty, rr.quoted_price,
                   pp.price_before_tax AS current_price, p.product_name, pr.producer_name
            FROM Restock_Request rr
            JOIN Producer_Product pp
                ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
            JOIN Product   p  ON p.product_id   = rr.product_id
            JOIN Producer  pr ON pr.producer_id = rr.producer_id
            WHERE rr.warehouse_id = %s AND rr.status = 'Pending'
              AND rr.quoted_price IS NOT NULL
              AND rr.quoted_price != pp.price_before_tax
        """, (warehouse_id,))
        price_alerts = cursor.fetchall()
        cursor.execute("""
            SELECT
                o.order_id, c.first_name, c.last_name,
                o.order_status, o.total_amount, o.total_items, o.created_at,
                GROUP_CONCAT(p.product_name, ' ×', oi.quantity
                    ORDER BY p.product_name SEPARATOR ' | ') AS items_summary
            FROM `Order` o
            JOIN Customer   c  ON o.customer_id  = c.customer_id
            JOIN Order_Item oi ON oi.order_id     = o.order_id
            JOIN Product    p  ON p.product_id    = oi.product_id
            WHERE o.warehouse_id = %s
              AND o.order_status IN ('CONFIRMED', 'DELIVERED')
            GROUP BY o.order_id, c.first_name, c.last_name,
                     o.order_status, o.total_amount, o.total_items, o.created_at
            ORDER BY o.created_at DESC LIMIT 30
        """, (warehouse_id,))
        customer_orders = cursor.fetchall()
        for o in customer_orders:
            if o['total_amount']:
                o['total_amount'] = float(o['total_amount'])
        return render_template("admin/admin.html",
            warehouse=warehouse, catalogue=catalogue,
            requests=requests_list, price_alerts=price_alerts,
            customer_orders=customer_orders)
    except Exception as e:
        return f"<h2>Dashboard error: {str(e)} <a href=/login>Back to Login</a></h2>", 500
    finally:
        if conn: conn.close()


@app.route("/warehouse/<int:warehouse_id>/send-request", methods=["POST"])
def send_request(warehouse_id):
    conn = None
    try:
        producer_id   = int(request.form["producer_id"])
        product_id    = int(request.form["product_id"])
        requested_qty = int(request.form["requested_qty"])
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT price_before_tax FROM Producer_Product WHERE producer_id=%s AND product_id=%s",
            (producer_id, product_id)
        )
        row = cursor.fetchone()
        if not row:
            flash("Product not found for this producer.", "danger")
            return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))
        cursor.execute("""
            INSERT INTO Restock_Request
                (warehouse_id, producer_id, product_id, requested_qty, quoted_price, status)
            VALUES (%s, %s, %s, %s, %s, 'Pending')
        """, (warehouse_id, producer_id, product_id, requested_qty, row["price_before_tax"]))
        conn.commit()
        flash("Restock request sent.", "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))


@app.route("/warehouse/<int:warehouse_id>/accept-price-change/<int:request_id>", methods=["POST"])
def accept_price_change(warehouse_id, request_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE Restock_Request rr
            JOIN Producer_Product pp
                ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
            SET rr.quoted_price = pp.price_before_tax
            WHERE rr.request_id = %s
        """, (request_id,))
        conn.commit()
        flash("New price accepted. Producer can now fulfill the request.", "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))


@app.route("/warehouse/<int:warehouse_id>/cancel-request/<int:request_id>", methods=["POST"])
def cancel_request(warehouse_id, request_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE Restock_Request SET status = 'Cancelled' WHERE request_id=%s AND status='Pending'",
            (request_id,)
        )
        conn.commit()
        flash("Request cancelled.", "warning")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))


@app.route("/warehouse/<int:warehouse_id>/deliver-order/<int:order_id>", methods=["POST"])
def deliver_order(warehouse_id, order_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE `Order` SET order_status = 'DELIVERED'
            WHERE order_id = %s AND warehouse_id = %s AND order_status = 'CONFIRMED'
        """, (order_id, warehouse_id))
        if cursor.rowcount == 0:
            flash(f"Order #{order_id} could not be updated.", "warning")
        else:
            conn.commit()
            flash(f"✓ Order #{order_id} marked as Delivered!", "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))


@app.route("/warehouse/<int:warehouse_id>/add-budget", methods=["POST"])
def add_budget(warehouse_id):
    conn = None
    try:
        amount = float(request.form.get("amount", 0))
        if amount <= 0:
            flash("Amount must be greater than 0.", "danger")
            return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "UPDATE Warehouse SET budget = budget + %s WHERE warehouse_id = %s",
            (amount, warehouse_id)
        )
        conn.commit()
        cursor.execute("SELECT budget FROM Warehouse WHERE warehouse_id = %s", (warehouse_id,))
        new_budget = float(cursor.fetchone()["budget"])
        flash(f"✓ Budget topped up by ₹{amount:,.0f}. New budget: ₹{new_budget:,.0f}", "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("warehouse_dashboard", warehouse_id=warehouse_id))


# =========================================================
# PRODUCER ROUTES
# =========================================================
@app.route("/producer/<int:producer_id>")
def producer_dashboard(producer_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM Producer WHERE producer_id = %s", (producer_id,))
        producer = cursor.fetchone()
        if not producer:
            return f"<h2>Producer ID {producer_id} not found. <a href=/login>Back to Login</a></h2>", 404
        cursor.execute("""
            SELECT p.product_id, p.product_name, pp.price_before_tax, pp.max_batch_limit
            FROM Producer_Product pp
            JOIN Product p ON pp.product_id = p.product_id
            WHERE pp.producer_id = %s ORDER BY p.product_name
        """, (producer_id,))
        products = cursor.fetchall()
        for p in products:
            p['price_before_tax'] = float(p['price_before_tax'])
        cursor.execute("""
            SELECT rr.request_id, p.product_name, w.warehouse_name,
                   rr.requested_qty, pp.price_before_tax
            FROM Restock_Request rr
            JOIN Product   p  ON rr.product_id  = p.product_id
            JOIN Warehouse w  ON rr.warehouse_id = w.warehouse_id
            JOIN Producer_Product pp
                ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
            WHERE rr.producer_id = %s AND rr.status = 'Pending'
            ORDER BY rr.created_at DESC
        """, (producer_id,))
        requests_list = cursor.fetchall()
        cursor.execute("""
            SELECT b.batch_id, p.product_name, w.warehouse_name,
                   b.quantity, b.unit_cost, b.arrival_date
            FROM Batch b
            JOIN Product   p ON b.product_id   = p.product_id
            JOIN Warehouse w ON b.warehouse_id = w.warehouse_id
            WHERE b.producer_id = %s ORDER BY b.arrival_date DESC
        """, (producer_id,))
        shipments = cursor.fetchall()
        return render_template("producer/producer.html",
            producer=producer, products=products,
            requests=requests_list, shipments=shipments)
    except Exception as e:
        return f"<h2>Dashboard error: {str(e)} <a href=/login>Back to Login</a></h2>", 500
    finally:
        if conn: conn.close()


@app.route("/producer/add-product/<int:producer_id>", methods=["POST"])
def add_product(producer_id):
    conn = None
    try:
        product_name     = request.form.get("product_name", "").strip()
        price_before_tax = request.form.get("price_before_tax", "").strip()
        max_batch_limit  = request.form.get("max_batch_limit", "").strip()
        if not all([product_name, price_before_tax, max_batch_limit]):
            flash("All fields are required.", "danger")
            return redirect(url_for("producer_dashboard", producer_id=producer_id))
        price = float(price_before_tax)
        limit = int(max_batch_limit)
        if price <= 0 or limit <= 0:
            flash("Price and batch limit must be > 0.", "danger")
            return redirect(url_for("producer_dashboard", producer_id=producer_id))
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        conn.start_transaction()
        cursor.execute("SELECT product_id FROM Product WHERE product_name = %s", (product_name,))
        existing = cursor.fetchone()
        if existing:
            product_id = existing["product_id"]
            cursor.execute(
                "SELECT 1 FROM Producer_Product WHERE producer_id=%s AND product_id=%s",
                (producer_id, product_id)
            )
            if cursor.fetchone():
                flash(f"'{product_name}' is already in your catalogue.", "warning")
                conn.rollback()
                return redirect(url_for("producer_dashboard", producer_id=producer_id))
        else:
            cursor.execute("INSERT INTO Product (product_name) VALUES (%s)", (product_name,))
            product_id = cursor.lastrowid
        cursor.execute("""
            INSERT INTO Producer_Product (producer_id, product_id, price_before_tax, max_batch_limit)
            VALUES (%s, %s, %s, %s)
        """, (producer_id, product_id, price, limit))
        conn.commit()
        flash(f"✓ '{product_name}' added at ₹{price:.2f}/unit!", "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("producer_dashboard", producer_id=producer_id))


@app.route("/producer/change-price/<int:producer_id>", methods=["POST"])
def change_price(producer_id):
    conn = None
    try:
        product_id = request.form.get("product_id")
        new_price  = float(request.form.get("new_price", "").strip())
        if not product_id or new_price <= 0:
            flash("Product and valid price are required.", "danger")
            return redirect(url_for("producer_dashboard", producer_id=producer_id))
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT price_before_tax FROM Producer_Product WHERE producer_id=%s AND product_id=%s",
            (producer_id, product_id)
        )
        old       = cursor.fetchone()
        old_price = float(old["price_before_tax"]) if old else 0
        cursor.execute(
            "UPDATE Producer_Product SET price_before_tax=%s WHERE producer_id=%s AND product_id=%s",
            (new_price, producer_id, product_id)
        )
        cursor.execute("""
            SELECT COUNT(*) AS cnt FROM Restock_Request
            WHERE producer_id=%s AND product_id=%s AND status='Pending'
        """, (producer_id, product_id))
        affected = cursor.fetchone()["cnt"]
        conn.commit()
        msg = f"✓ Price updated ₹{old_price:.2f} → ₹{new_price:.2f}."
        if affected > 0:
            msg += f" ⚠ {affected} pending request(s) will see a price-change alert."
        flash(msg, "success")
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    return redirect(url_for("producer_dashboard", producer_id=producer_id))


@app.route("/producer/fulfill/<int:request_id>", methods=["POST"])
def fulfill_request(request_id):
    conn = None; req = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        conn.start_transaction()
        cursor.execute("""
            SELECT rr.*, pp.price_before_tax AS current_price
            FROM Restock_Request rr
            JOIN Producer_Product pp
                ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
            WHERE rr.request_id = %s AND rr.status = 'Pending'
            FOR UPDATE
        """, (request_id,))
        req = cursor.fetchone()
        if not req:
            flash("Request already fulfilled, cancelled, or not found.", "warning")
            conn.rollback()
            return redirect(request.referrer or "/")
        if req["quoted_price"] is not None and \
                abs(float(req["quoted_price"]) - float(req["current_price"])) > 0.001:
            conn.rollback()
            flash(
                f"⚠ Cannot fulfill — price changed from ₹{float(req['quoted_price']):.2f} "
                f"to ₹{float(req['current_price']):.2f}. Waiting for warehouse to accept.",
                "warning"
            )
            return redirect(url_for("producer_dashboard", producer_id=req["producer_id"]))
        fulfill_price = float(req["current_price"])
        total_val     = req["requested_qty"] * fulfill_price
        cursor.execute("""
            INSERT INTO Batch
                (producer_id, product_id, warehouse_id, request_id, quantity, unit_cost, arrival_date)
            VALUES (%s, %s, %s, %s, %s, %s, CURDATE())
        """, (req["producer_id"], req["product_id"], req["warehouse_id"],
              request_id, req["requested_qty"], fulfill_price))
        cursor.execute(
            "UPDATE Producer SET earnings = earnings + %s WHERE producer_id = %s",
            (total_val, req["producer_id"])
        )
        cursor.execute(
            "UPDATE Restock_Request SET status = 'Fulfilled' WHERE request_id = %s",
            (request_id,)
        )
        conn.commit()
        flash(
            f"✓ Fulfilled! {req['requested_qty']} units at ₹{fulfill_price:.2f}/unit. "
            f"Earnings +₹{total_val:.2f}", "success"
        )
    except Exception as e:
        if conn: conn.rollback()
        flash(f"Database error: {str(e)}", "danger")
    finally:
        if conn: conn.close()
    producer_id = req["producer_id"] if req else 1
    return redirect(url_for("producer_dashboard", producer_id=producer_id))


# =========================================================
# CUSTOMER ROUTES
# =========================================================
@app.route("/customer/<int:customer_id>")
def customer_dashboard(customer_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM Customer WHERE customer_id = %s", (customer_id,))
        customer = cursor.fetchone()
        if not customer:
            return f"<h2>Customer ID {customer_id} not found. <a href=/login>Back to Login</a></h2>", 404
        cursor.execute("SELECT balance FROM Wallet WHERE customer_id = %s", (customer_id,))
        wallet_row = cursor.fetchone()
        wallet = wallet_row if wallet_row else {"balance": 0.00}
        wallet['balance'] = float(wallet['balance'])
        cursor.execute("""
            SELECT p.product_id, p.product_name,
                   COALESCE(p.category, 'General') AS category,
                   MIN(pp.price_before_tax) AS price_before_tax
            FROM Product p
            JOIN Producer_Product pp ON p.product_id = pp.product_id
            JOIN Producer pr ON pp.producer_id = pr.producer_id
            WHERE pr.approval_status = 'Approved'
            GROUP BY p.product_id, p.product_name, p.category
            ORDER BY p.category, p.product_name
        """)
        products = cursor.fetchall()
        for p in products:
            p['price_before_tax'] = float(p['price_before_tax'])
        cursor.execute("SELECT warehouse_id FROM Warehouse ORDER BY warehouse_id LIMIT 1")
        wh = cursor.fetchone()
        default_warehouse_id = wh["warehouse_id"] if wh else 1
        return render_template("customer/customer.html",
            customer=customer, wallet=wallet,
            products=products, default_warehouse_id=default_warehouse_id)
    except Exception as e:
        return f"<h2>Dashboard error: {str(e)} <a href=/login>Back to Login</a></h2>", 500
    finally:
        if conn: conn.close()


@app.route("/customer/<int:customer_id>/balance")
def customer_balance(customer_id):
    conn = None
    try:
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT balance FROM Wallet WHERE customer_id = %s", (customer_id,))
        row     = cursor.fetchone()
        balance = float(row["balance"]) if row else 0.0
        return jsonify({"balance": balance}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if conn: conn.close()


@app.route("/customer/<int:customer_id>/checkout", methods=["POST"])
def customer_checkout(customer_id):
    conn = None
    try:
        data         = request.json
        items        = data.get("items", [])
        warehouse_id = data.get("warehouse_id", 1)
        if not items:
            return jsonify({"error": "Cart is empty"}), 400
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        conn.start_transaction()
        cursor.execute(
            "INSERT INTO `Order` (customer_id, warehouse_id, order_status) VALUES (%s, %s, 'CREATED')",
            (customer_id, warehouse_id)
        )
        order_id = cursor.lastrowid
        for item in items:
            cursor.execute(
                "INSERT INTO Order_Item (order_id, product_id, quantity, unit_price) VALUES (%s, %s, %s, %s)",
                (order_id, item["product_id"], item["qty"], item["unit_price"])
            )
        conn.commit()
        conn.start_transaction()
        cursor.execute(
            "UPDATE `Order` SET order_status = 'CONFIRMED' WHERE order_id = %s",
            (order_id,)
        )
        conn.commit()
        return jsonify({"message": "Order placed successfully", "order_id": order_id}), 201
    except Exception as e:
        if conn:
            try: conn.rollback()
            except: pass
        error_msg = str(e)
        if "1644" in error_msg or "45000" in error_msg:
            import re
            match = re.search(r"'(.+?)'", error_msg)
            clean = match.group(1) if match else error_msg
            return jsonify({"error": clean}), 400
        return jsonify({"error": error_msg}), 500
    finally:
        if conn: conn.close()


@app.route("/customer/<int:customer_id>/add-funds", methods=["POST"])
def add_funds(customer_id):
    conn = None
    try:
        data   = request.json
        amount = float(data.get("amount", 0))
        if amount <= 0:
            return jsonify({"error": "Amount must be greater than 0"}), 400
        conn   = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT wallet_id FROM Wallet WHERE customer_id = %s", (customer_id,))
        existing = cursor.fetchone()
        if existing:
            cursor.execute(
                "UPDATE Wallet SET balance = balance + %s WHERE customer_id = %s",
                (amount, customer_id)
            )
        else:
            cursor.execute(
                "INSERT INTO Wallet (customer_id, balance) VALUES (%s, %s)",
                (customer_id, amount)
            )
        conn.commit()
        cursor.execute("SELECT balance FROM Wallet WHERE customer_id = %s", (customer_id,))
        new_balance = float(cursor.fetchone()["balance"])
        return jsonify({"message": "Funds added", "new_balance": new_balance}), 200
    except Exception as e:
        if conn: conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if conn: conn.close()


# =========================================================
# ERROR HANDLERS
# =========================================================
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Route not found"}), 404

@app.errorhandler(500)
def server_error(e):
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    app.run(debug=True)