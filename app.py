from flask import Flask, jsonify
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)

# ---------- DB CONNECTION ----------
def get_db_connection():
    return mysql.connector.connect(
        host="localhost",
        user="root",
        password="Anuradha@babu1",   # your MySQL password
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

        cursor.execute(
            "SELECT producer_id, producer_name FROM Producer;"
        )
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

# ---------- RUN SERVER ----------
if __name__ == "__main__":
    app.run(debug=True)
