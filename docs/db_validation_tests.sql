-- =========================================
-- Database Validation & Constraint Stress Tests
-- =========================================
-- NOTE:
-- All tests below are EXPECTED TO FAIL.
-- They validate business rules, constraints, and triggers.
-- =========================================

USE supplychain_db;

-- =========================================
-- TEST 1: Batch exceeding warehouse capacity
-- Expected: FAIL
-- Reason: Warehouse capacity constraint enforced by trigger
-- =========================================
-- Warehouse total_capacity = 1000, used_capacity already high
INSERT INTO Batch (
    producer_id, product_id, warehouse_id,
    quantity, unit_cost, arrival_date
)
VALUES (1, 1, 1, 5000, 10.00, CURDATE());
-- Expected Error: Warehouse capacity exceeded


-- =========================================
-- TEST 2: Order item with insufficient inventory
-- Expected: FAIL
-- Reason: Cannot reserve more stock than available
-- =========================================
INSERT INTO Order_Item (order_id, product_id, quantity)
VALUES (1, 1, 10000);
-- Expected Error: Insufficient stock available


-- =========================================
-- TEST 3: Confirm order with insufficient wallet balance
-- Expected: FAIL
-- Reason: Wallet debit trigger blocks confirmation
-- =========================================
-- Reduce wallet balance artificially
UPDATE Wallet
SET balance = 1
WHERE customer_id = 1;

-- Try to confirm order
UPDATE `Order`
SET order_status = 'CONFIRMED'
WHERE order_id = 2;
-- Expected Error: Insufficient wallet balance


-- =========================================
-- TEST 4: Duplicate producer-product mapping
-- Expected: FAIL
-- Reason: Composite primary key (producer_id, product_id)
-- =========================================
INSERT INTO Producer_Product (producer_id, product_id, price_before_tax)
VALUES (1, 1, 99.99);
-- Expected Error: Duplicate entry for primary key
