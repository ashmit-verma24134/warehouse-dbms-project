from flask import Flask, jsonify, request
import mysql.connector
from mysql.connector import Error
from flask import request



app = Flask(__name__)

# ---------- DB CONNECTION ----------
def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="root",
        password="Anuradha@babu1",
        database="supplychain_db"
    )

# ---------- HOME ----------
@app.route("/")
def home():
    return "Warehouse Management System – Backend Running"

# ---------- HEALTH CHECK ----------
@app.route("/health")
def health():
    try:
        conn = get_db_connection()
        if conn.is_connected():
            conn.close()
            return "DB connected", 200
    except Error:
        return "DB not connected", 500

# ---------- READ-ONLY PRODUCERS ----------
@app.route("/producers")
def get_producers():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("SELECT producer_id, producer_name FROM Producer;")
        producers = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify(producers), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500

# ---------- READ-ONLY INVENTORY ----------
@app.route("/inventory")
def inventory():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT w.warehouse_name,
               p.product_name,
               i.available_qty
        FROM Inventory i
        JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
        JOIN Product p ON i.product_id = p.product_id;
        """
        cursor.execute(query)
        inventory_data = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify(inventory_data), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500

# ---------- READ-ONLY BATCHES ----------
@app.route("/batches")
def batches():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT b.batch_id,
               p.product_name,
               w.warehouse_name,
               b.batch_qty,
               b.expiry_date
        FROM Batch b
        JOIN Product p ON b.product_id = p.product_id
        JOIN Warehouse w ON b.warehouse_id = w.warehouse_id;
        """
        cursor.execute(query)
        batch_data = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify(batch_data), 200
    except Error as e:
        return jsonify({"error": str(e)}), 500

# =========================================================
# ================= DAY 4 – TRANSACTIONS ==================
# =========================================================

# ---------- PLACE ORDER (TRANSACTION DEMO) ----------
@app.route("/place-order", methods=["POST"])
def place_order():
    conn = None
    cursor = None
    try:
        data = request.json
        customer_id = data["customer_id"]
        warehouse_id = data["warehouse_id"]
        product_id = data["product_id"]
        quantity = data["quantity"]

        conn = get_db_connection()
        cursor = conn.cursor()

        # START TRANSACTION
        conn.start_transaction()

        # Insert into Order table (BACKTICKS + warehouse_id)
        cursor.execute(
            "INSERT INTO `Order` (customer_id, warehouse_id, order_status) VALUES (%s, %s, %s)",
            (customer_id, warehouse_id, "CREATED")
        )
        order_id = cursor.lastrowid

        # Insert into Order_Item
        cursor.execute(
            "INSERT INTO Order_Item (order_id, product_id, quantity) VALUES (%s, %s, %s)",
            (order_id, product_id, quantity)
        )

        # COMMIT
        conn.commit()

        return jsonify({
            "message": "Order placed successfully",
            "order_id": order_id
        }), 201

    except Exception as e:
        if conn:
            conn.rollback()

        return jsonify({
            "error": "Transaction failed, rolled back",
            "details": str(e)
        }), 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

# ---------- CONFIRM ORDER ----------
@app.route("/confirm-order", methods=["POST"])
def confirm_order():
    try:
        data = request.json
        order_id = data["order_id"]

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            "UPDATE Order_Table SET order_status = %s WHERE order_id = %s",
            ("CONFIRMED", order_id)
        )

        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "message": "Order confirmed successfully"
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/test-failure", methods=["POST"])
def test_failure():
    conn = None
    cursor = None
    try:
        data = request.json
        customer_id = data["customer_id"]
        warehouse_id = data["warehouse_id"]
        product_id = data["product_id"]
        quantity = data["quantity"]

        conn = get_db_connection()
        cursor = conn.cursor()

        # ---------- ISOLATION LEVEL (CONCEPTUAL DEMO) ----------
        # SERIALIZABLE ensures:
        # - No lost updates
        # - No dirty reads
        # - Transactions behave as if executed one after another
        cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")

        # ---------- START TRANSACTION ----------
        conn.start_transaction()

        # Insert into Order
        cursor.execute(
            "INSERT INTO `order` (customer_id, warehouse_id, order_status) VALUES (%s, %s, %s)",
            (customer_id, warehouse_id, "CREATED")
        )
        order_id = cursor.lastrowid

        # Insert into Order_Item (this reserves inventory via trigger)
        cursor.execute(
            "INSERT INTO Order_Item (order_id, product_id, quantity) VALUES (%s, %s, %s)",
            (order_id, product_id, quantity)
        )

        # ---------- FORCE FAILURE ----------
        x = 1 / 0   # Division by zero (intentional failure)

        # ---------- COMMIT (never reached) ----------
        conn.commit()

        return {"message": "This should never execute"}

    except Exception as e:
        # ---------- ROLLBACK ----------
        if conn:
            conn.rollback()

        return {
            "error": "Forced failure occurred, transaction rolled back",
            "details": str(e)
        }, 500

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.route("/demo/inventory")
def demo_inventory():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT w.warehouse_name,
               p.product_name,
               i.available_qty,
               i.reserved_qty
        FROM Inventory i
        JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
        JOIN Product p ON i.product_id = p.product_id;
        """
        cursor.execute(query)
        data = cursor.fetchall()

        return jsonify(data), 200

    except Exception:
        return jsonify({"error": "Unable to fetch inventory data"}), 500

    finally:
        cursor.close()
        conn.close()
@app.route("/demo/orders")
def demo_orders():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT o.order_id,
               c.customer_name,
               w.warehouse_name,
               o.order_status,
               o.created_at
        FROM `order` o
        JOIN Customer c ON o.customer_id = c.customer_id
        JOIN Warehouse w ON o.warehouse_id = w.warehouse_id
        ORDER BY o.order_id DESC;
        """
        cursor.execute(query)
        orders = cursor.fetchall()

        return jsonify(orders), 200

    except Exception:
        return jsonify({"error": "Unable to fetch orders"}), 500

    finally:
        cursor.close()
        conn.close()
@app.route("/demo/wallets")
def demo_wallets():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT c.customer_name,
               w.balance
        FROM Wallet w
        JOIN Customer c ON w.customer_id = c.customer_id;
        """
        cursor.execute(query)
        wallets = cursor.fetchall()

        return jsonify(wallets), 200

    except Exception:
        return jsonify({"error": "Unable to fetch wallet data"}), 500

    finally:
        cursor.close()
        conn.close()

# =====================================================
# ANALYTICS ROUTES (READ-ONLY)
# =====================================================

@app.route("/analytics/low-stock")
def analytics_low_stock():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("SELECT * FROM v_low_stock_products;")
        data = cursor.fetchall()

        return jsonify(data), 200

    except Exception:
        return jsonify({
            "error": "Unable to fetch low stock analytics"
        }), 500

    finally:
        cursor.close()
        conn.close()


@app.route("/analytics/warehouse-summary")
def analytics_warehouse_summary():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("SELECT * FROM v_warehouse_summary;")
        data = cursor.fetchall()

        return jsonify(data), 200

    except Exception:
        return jsonify({
            "error": "Unable to fetch warehouse summary analytics"
        }), 500

    finally:
        cursor.close()
        conn.close()


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Route not found"}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({"error": "Internal server error"}), 500




# ---------- RUN SERVER ----------
if __name__ == "__main__":
    app.run(debug=True)
