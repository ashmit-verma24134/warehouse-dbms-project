USE supplychain_db;

-- ============================================================
-- TASK 4 – SQL QUERIES FOR SUPPLY CHAIN MANAGEMENT SYSTEM
-- ============================================================

-- ============================================================
-- 1. View all producers
-- ============================================================
SELECT
producer_id,
producer_name,
phone,
email
FROM Producer;

-- ============================================================
-- 2. View all products
-- ============================================================
SELECT
product_id,
product_name,
category
FROM Product;

-- ============================================================
-- 3. Producer – Product – Price mapping
-- ============================================================
SELECT
pr.producer_name,
p.product_name,
pp.price_before_tax
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
JOIN Product p ON pp.product_id = p.product_id
ORDER BY pr.producer_name;

-- ============================================================
-- 4. Products supplied by specific producer
-- ============================================================
SELECT
p.product_name,
pp.price_before_tax
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
JOIN Product p ON pp.product_id = p.product_id
WHERE pr.producer_name = 'Amul Dairy Ltd';

-- ============================================================
-- 5. Producers supplying a specific product
-- ============================================================
SELECT
pr.producer_name,
pp.price_before_tax
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
JOIN Product p ON pp.product_id = p.product_id
WHERE p.product_name = 'Mirror';

-- ============================================================
-- 6. Average product price per producer
-- ============================================================
SELECT
pr.producer_name,
ROUND(AVG(pp.price_before_tax),2) AS average_price
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
GROUP BY pr.producer_name;

-- ============================================================
-- 7. Most expensive product per producer
-- ============================================================
SELECT
pr.producer_name,
p.product_name,
pp.price_before_tax
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
JOIN Product p ON pp.product_id = p.product_id
WHERE pp.price_before_tax = (
SELECT MAX(pp2.price_before_tax)
FROM Producer_Product pp2
WHERE pp2.producer_id = pp.producer_id
);

-- ============================================================
-- 8. Producers supplying more than 2 products
-- ============================================================
SELECT
pr.producer_name,
COUNT(pp.product_id) AS product_count
FROM Producer_Product pp
JOIN Producer pr ON pp.producer_id = pr.producer_id
GROUP BY pr.producer_name
HAVING COUNT(pp.product_id) > 2;

-- ============================================================
-- 9. View inventory stock in warehouse
-- ============================================================
SELECT
w.warehouse_name,
p.product_name,
i.available_qty,
i.reserved_qty
FROM Inventory i
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
JOIN Product p ON i.product_id = p.product_id;

-- ============================================================
-- 10. Low stock products (VIEW)
-- ============================================================
SELECT *
FROM v_low_stock_products;

-- ============================================================
-- 11. Warehouse revenue report
-- ============================================================
SELECT
w.warehouse_name,
SUM(oi.quantity * oi.unit_price_with_tax) AS total_revenue
FROM `Order` o
JOIN Order_Item oi ON o.order_id = oi.order_id
JOIN Warehouse w ON o.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_name;

-- ============================================================
-- 12. Warehouse cost report
-- ============================================================
SELECT *
FROM v_warehouse_cost;

-- ============================================================
-- 13. Warehouse profit report
-- ============================================================
SELECT *
FROM v_warehouse_profit;

-- ============================================================
-- 14. Trigger Demonstration – Batch insert
-- This will update Inventory automatically
-- ============================================================
INSERT INTO Batch
(producer_id, product_id, warehouse_id, quantity, unit_cost, arrival_date)
VALUES
(1,1,1,10,30,CURDATE());

-- ============================================================
-- 15. Check inventory after trigger execution
-- ============================================================
SELECT *
FROM Inventory
WHERE product_id = 1;
