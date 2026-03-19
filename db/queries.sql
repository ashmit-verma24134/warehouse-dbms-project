USE supplychain_db;

-- Q1: All producers with their products and GST price
SELECT
    pr.producer_id,
    pr.producer_name,
    pr.approval_status,
    p.product_name,
    pp.price_before_tax,
    ROUND(pp.price_before_tax * 1.20, 2) AS price_after_gst,
    pp.max_batch_limit
FROM Producer pr
JOIN Producer_Product pp ON pr.producer_id = pp.producer_id
JOIN Product p           ON pp.product_id  = p.product_id
ORDER BY pr.producer_name, p.product_name;


-- Q2: Producer summary - products, batches, total earned
SELECT
    pr.producer_name,
    pr.approval_status,
    COUNT(DISTINCT pp.product_id)              AS total_products,
    COUNT(DISTINCT b.batch_id)                 AS total_batches,
    COALESCE(SUM(b.quantity * b.unit_cost), 0) AS total_earned
FROM Producer pr
LEFT JOIN Producer_Product pp ON pr.producer_id = pp.producer_id
LEFT JOIN Batch b             ON pr.producer_id = b.producer_id
GROUP BY pr.producer_id, pr.producer_name, pr.approval_status
ORDER BY total_earned DESC;


-- Q3: Inventory stock status per product
SELECT
    w.warehouse_name,
    p.product_name,
    p.category,
    i.available_qty,
    i.reserved_qty,
    (i.available_qty + i.reserved_qty) AS total_stock,
    CASE
        WHEN i.available_qty = 0   THEN 'OUT OF STOCK'
        WHEN i.available_qty <= 20 THEN 'LOW STOCK'
        ELSE                            'IN STOCK'
    END AS stock_status
FROM Inventory i
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
JOIN Product   p ON i.product_id   = p.product_id
ORDER BY i.available_qty ASC;


-- Q4: Customer order summary with wallet balance
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    w.balance                               AS wallet_balance,
    COUNT(o.order_id)                       AS total_orders,
    COALESCE(SUM(o.total_amount), 0)        AS total_spent,
    MAX(o.created_at)                       AS last_order_date
FROM Customer c
LEFT JOIN Wallet  w ON c.customer_id = w.customer_id
LEFT JOIN `Order` o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, w.balance
ORDER BY total_spent DESC;


-- Q5: Full order breakdown with item-level detail (5 table join)
SELECT
    o.order_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    w.warehouse_name,
    p.product_name,
    oi.quantity,
    oi.unit_price                          AS price_before_tax,
    oi.unit_price_with_tax                 AS price_after_tax,
    (oi.quantity * oi.unit_price_with_tax) AS line_total,
    o.order_status,
    o.created_at
FROM `Order` o
JOIN Customer   c  ON o.customer_id  = c.customer_id
JOIN Warehouse  w  ON o.warehouse_id = w.warehouse_id
JOIN Order_Item oi ON o.order_id     = oi.order_id
JOIN Product    p  ON oi.product_id  = p.product_id
ORDER BY o.order_id DESC, p.product_name;


-- Q6: Restock requests showing price change since request was made
SELECT
    rr.request_id,
    pr.producer_name,
    p.product_name,
    w.warehouse_name,
    rr.requested_qty,
    rr.quoted_price                                 AS price_when_requested,
    pp.price_before_tax                             AS current_price,
    ROUND(pp.price_before_tax - rr.quoted_price, 2) AS price_change,
    rr.status,
    rr.created_at
FROM Restock_Request rr
JOIN Producer         pr ON rr.producer_id  = pr.producer_id
JOIN Product          p  ON rr.product_id   = p.product_id
JOIN Warehouse        w  ON rr.warehouse_id = w.warehouse_id
JOIN Producer_Product pp ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
ORDER BY rr.created_at DESC;


-- Q7: Producers who never shipped a batch (anti-join using LEFT JOIN + IS NULL)
SELECT
    pr.producer_id,
    pr.producer_name,
    pr.email,
    pr.approval_status,
    pr.earnings
FROM Producer pr
LEFT JOIN Batch b ON pr.producer_id = b.producer_id
WHERE b.batch_id IS NULL
ORDER BY pr.producer_name;


-- Q8: Low stock products using view
SELECT
    v.warehouse_name,
    v.product_name,
    v.available_qty,
    v.min_threshold,
    (v.min_threshold - v.available_qty) AS units_needed_to_reorder
FROM v_low_stock_products v
ORDER BY units_needed_to_reorder DESC;


-- Q9: Most expensive product per category (correlated subquery)
SELECT
    p.category,
    p.product_name,
    pp.price_before_tax AS highest_price,
    pr.producer_name
FROM Product p
JOIN Producer_Product pp ON p.product_id   = pp.product_id
JOIN Producer         pr ON pp.producer_id = pr.producer_id
WHERE pp.price_before_tax = (
    SELECT MAX(pp2.price_before_tax)
    FROM Producer_Product pp2
    JOIN Product p2 ON pp2.product_id = p2.product_id
    WHERE p2.category = p.category
)
ORDER BY p.category;


-- Q10: Customers with more than 1 order (HAVING on aggregate)
SELECT
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(o.order_id)                       AS order_count,
    SUM(o.total_amount)                     AS total_spent,
    ROUND(AVG(o.total_amount), 2)           AS avg_order_value
FROM Customer c
JOIN `Order` o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(o.order_id) > 1
ORDER BY total_spent DESC;


-- Q11: Batch cost running total (window function)
SELECT
    b.batch_id,
    b.arrival_date,
    pr.producer_name,
    p.product_name,
    b.quantity,
    b.unit_cost,
    (b.quantity * b.unit_cost) AS batch_cost,
    SUM(b.quantity * b.unit_cost)
        OVER (ORDER BY b.arrival_date, b.batch_id
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        AS running_total_cost
FROM Batch b
JOIN Producer pr ON b.producer_id = pr.producer_id
JOIN Product  p  ON b.product_id  = p.product_id
WHERE b.warehouse_id = 1
ORDER BY b.arrival_date, b.batch_id;


-- Q12: Producer earnings ranking (RANK, DENSE_RANK, ROW_NUMBER)
SELECT
    producer_name,
    earnings,
    approval_status,
    RANK()       OVER (ORDER BY earnings DESC) AS rank_position,
    DENSE_RANK() OVER (ORDER BY earnings DESC) AS dense_rank,
    ROW_NUMBER() OVER (ORDER BY earnings DESC) AS row_num,
    ROUND(earnings / NULLIF(SUM(earnings) OVER(), 0) * 100, 1) AS pct_share
FROM Producer
ORDER BY rank_position;


-- Q13: Revenue by producer and product with subtotals (ROLLUP)
SELECT
    COALESCE(pr.producer_name, '=== GRAND TOTAL ===') AS producer,
    COALESCE(p.product_name,   '--- Subtotal ---')    AS product,
    SUM(b.quantity)               AS total_units_supplied,
    SUM(b.quantity * b.unit_cost) AS total_revenue
FROM Batch b
JOIN Producer pr ON b.producer_id = pr.producer_id
JOIN Product  p  ON b.product_id  = p.product_id
GROUP BY pr.producer_name, p.product_name WITH ROLLUP
HAVING total_revenue IS NOT NULL
ORDER BY producer, product;


-- TRIGGER DEMO 1: trg_before_batch_insert
-- inserting a batch auto-updates inventory + deducts warehouse budget
SELECT 'BEFORE' AS stage, p.product_name, i.available_qty, w.used_capacity, w.budget
FROM Inventory i
JOIN Product   p ON i.product_id   = p.product_id
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
WHERE i.product_id = 1 AND i.warehouse_id = 1;

INSERT INTO Batch (producer_id, product_id, warehouse_id, quantity, unit_cost, arrival_date)
VALUES (1, 1, 1, 50, 30.00, CURDATE());

SELECT 'AFTER' AS stage, p.product_name, i.available_qty, w.used_capacity, w.budget
FROM Inventory i
JOIN Product   p ON i.product_id   = p.product_id
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
WHERE i.product_id = 1 AND i.warehouse_id = 1;


-- TRIGGER DEMO 2: trg_after_order_confirm
-- confirming an order auto-debits customer wallet
SELECT 'BEFORE_CONFIRM' AS stage, balance FROM Wallet WHERE customer_id = 1;

UPDATE `Order` SET order_status = 'CONFIRMED' WHERE order_id = 1 AND order_status = 'CREATED';

SELECT 'AFTER_CONFIRM' AS stage, balance FROM Wallet WHERE customer_id = 1;


-- TRIGGER DEMO 3: trg_audit_price_change
-- changing a price auto-logs it in Audit_Log
SELECT 'BEFORE_PRICE' AS stage, price_before_tax FROM Producer_Product WHERE producer_id = 1 AND product_id = 1;

UPDATE Producer_Product SET price_before_tax = 35.00 WHERE producer_id = 1 AND product_id = 1;

SELECT 'AFTER_PRICE' AS stage, log_id, changed_field, old_value, new_value, changed_at
FROM Audit_Log WHERE table_name = 'Producer_Product' ORDER BY log_id DESC LIMIT 1;

UPDATE Producer_Product SET price_before_tax = 30.00 WHERE producer_id = 1 AND product_id = 1;