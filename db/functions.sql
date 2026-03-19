USE supplychain_db;




DROP FUNCTION IF EXISTS fn_price_with_tax;
DROP FUNCTION IF EXISTS fn_wallet_balance;
DROP FUNCTION IF EXISTS fn_stock_available;
DROP FUNCTION IF EXISTS fn_producer_total_revenue;


-- FUNCTION : fn_price_with_tax
-- Given price before tax, returns price with 20% GST
-- Usage: SELECT fn_price_with_tax(100.00) → 120.00

DELIMITER $$
CREATE FUNCTION fn_price_with_tax(p_price DECIMAL(10,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    RETURN ROUND(p_price * 1.20, 2);
END$$
DELIMITER ;


-- FUNCTION : fn_wallet_balance
-- Returns current wallet balance for a customer
-- Usage: SELECT fn_wallet_balance(1) → 1500.00

DELIMITER $$
CREATE FUNCTION fn_wallet_balance(p_customer_id INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_balance DECIMAL(10,2) DEFAULT 0.00;
    SELECT balance INTO v_balance
    FROM Wallet WHERE customer_id = p_customer_id;
    RETURN COALESCE(v_balance, 0.00);
END$$
DELIMITER ;


-- FUNCTION : fn_stock_available
-- Returns available stock for a product in a warehouse
-- Usage: SELECT fn_stock_available(1, 1) → 195

DELIMITER $$
CREATE FUNCTION fn_stock_available(p_product_id INT, p_warehouse_id INT)
RETURNS INT
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_qty INT DEFAULT 0;
    SELECT available_qty INTO v_qty
    FROM Inventory
    WHERE product_id = p_product_id AND warehouse_id = p_warehouse_id;
    RETURN COALESCE(v_qty, 0);
END$$
DELIMITER ;


-- FUNCTION : fn_producer_total_revenue
-- Returns total revenue earned by a producer across all batches
-- Usage: SELECT fn_producer_total_revenue(1) → 45000.00

DELIMITER $$
CREATE FUNCTION fn_producer_total_revenue(p_producer_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;
    SELECT COALESCE(SUM(quantity * unit_cost), 0.00) INTO v_total
    FROM Batch WHERE producer_id = p_producer_id;
    RETURN v_total;
END$$
DELIMITER ;


-- testing of all 4 functions

SELECT fn_price_with_tax(100.00)        AS price_with_tax;
SELECT fn_wallet_balance(1)             AS customer_1_balance;
SELECT fn_stock_available(1, 1)         AS amul_milk_stock;
SELECT fn_producer_total_revenue(1)     AS amul_total_revenue;

-- Key demo query — use all functions together in one SELECT
SELECT
    p.product_name,
    pp.price_before_tax,
    fn_price_with_tax(pp.price_before_tax)  AS price_after_gst,
    fn_stock_available(p.product_id, 1)     AS stock_available
FROM Product p
JOIN Producer_Product pp ON p.product_id = pp.product_id
ORDER BY p.product_name;