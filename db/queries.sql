-- =========================================
-- Supply Chain Database Queries
-- =========================================

USE supplychain_db;

-- =========================================
-- 1. View all producers
-- =========================================
SELECT * FROM Producer;

-- =========================================
-- 2. View all products
-- =========================================
SELECT * FROM Product;

-- =========================================
-- 3. View producer–product–price mapping
-- =========================================
SELECT
    p.producer_name,
    pr.product_name,
    pp.price_before_tax
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
JOIN Product pr ON pp.product_id = pr.product_id
ORDER BY p.producer_name;

-- =========================================
-- 4. Products supplied by a specific producer
-- =========================================
SELECT
    p.producer_name,
    pr.product_name,
    pp.price_before_tax
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
JOIN Product pr ON pp.product_id = pr.product_id
WHERE p.producer_name = 'Pet Food Pvt Ltd';

-- =========================================
-- 5. Producers supplying a specific product
-- =========================================
SELECT
    pr.product_name,
    p.producer_name,
    pp.price_before_tax
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
JOIN Product pr ON pp.product_id = pr.product_id
WHERE pr.product_name = 'Mirror';

-- =========================================
-- 6. Average price per producer
-- =========================================
SELECT
    p.producer_name,
    AVG(pp.price_before_tax) AS avg_price
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
GROUP BY p.producer_name;

-- =========================================
-- 7. Most expensive product per producer
-- =========================================
SELECT
    p.producer_name,
    pr.product_name,
    pp.price_before_tax
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
JOIN Product pr ON pp.product_id = pr.product_id
WHERE pp.price_before_tax = (
    SELECT MAX(pp2.price_before_tax)
    FROM Producer_Product pp2
    WHERE pp2.producer_id = pp.producer_id
);

-- =========================================
-- 8. Producers supplying more than 2 products
-- =========================================
SELECT
    p.producer_name,
    COUNT(pp.product_id) AS product_count
FROM Producer_Product pp
JOIN Producer p ON pp.producer_id = p.producer_id
GROUP BY p.producer_name
HAVING COUNT(pp.product_id) > 2;
