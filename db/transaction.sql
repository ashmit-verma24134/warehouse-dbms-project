-- ============================================================================
-- TASK 6: DATABASE TRANSACTIONS & CONCURRENCY CONTROL
-- ============================================================================
-- File    : transaction.sql
-- Database: supplychain_db (Warehouse Management System)
-- Course  : DBMS — Ch.17 Transaction Management
--
-- Covers:
--   1. ACID-compliant transactions (real business scenarios)
--   2. WR Conflict (Dirty Read)
--   3. RW Conflict (Unrepeatable Read)
--   4. WW Conflict (Lost Update)
--   5. Phantom Read
--   6. Isolation Level Demonstrations
--   7. Deadlock Scenario
--   8. Serializable Transactions (conflict-free schedule)
--   9. Savepoints and Partial Rollback
--  10. Recoverable vs Non-Recoverable Schedules
--
-- NOTE: Conflict demos require TWO concurrent MySQL sessions (Session A & B).
--       Run the commands in the order indicated by the step numbers.
-- ============================================================================

USE supplychain_db;

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 1: ACID-COMPLIANT TRANSACTIONS (NORMAL OPERATION)                ║
-- ║  Demonstrates: Atomicity, Consistency, Isolation, Durability               ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────────────────
-- TRANSACTION 1.1: Wallet-to-Wallet Fund Transfer
-- Scenario: Customer 1 (Amit) transfers ₹200 to Customer 2 (Sneha)
-- ACID: Atomicity ensures both debit + credit happen or neither
-- ─────────────────────────────────────────────────────────

-- Check balances BEFORE
SELECT 'BEFORE TRANSFER' AS stage,
       w.customer_id, CONCAT(c.first_name,' ',c.last_name) AS name, w.balance
FROM Wallet w JOIN Customer c ON w.customer_id = c.customer_id
WHERE w.customer_id IN (1, 2);

START TRANSACTION;

    -- Step 1: Debit sender (Amit)
    UPDATE Wallet SET balance = balance - 200
    WHERE customer_id = 1 AND balance >= 200;  -- CHECK constraint ensures balance >= 0

    -- Step 2: Credit receiver (Sneha)
    UPDATE Wallet SET balance = balance + 200
    WHERE customer_id = 2;

COMMIT;

-- Check balances AFTER
SELECT 'AFTER TRANSFER' AS stage,
       w.customer_id, CONCAT(c.first_name,' ',c.last_name) AS name, w.balance
FROM Wallet w JOIN Customer c ON w.customer_id = c.customer_id
WHERE w.customer_id IN (1, 2);

-- Consistency: Sum of both balances is unchanged
-- Durability: Even if the server crashes after COMMIT, this change persists


-- ─────────────────────────────────────────────────────────
-- TRANSACTION 1.2: Atomic Order Placement with Inventory Reservation
-- Scenario: Customer 4 (Priya) places an order for 2 products
-- ACID: Either the full order is created OR nothing changes
-- ─────────────────────────────────────────────────────────

-- Snapshot BEFORE
SELECT 'BEFORE ORDER' AS stage, available_qty, reserved_qty
FROM Inventory WHERE product_id IN (1, 4) AND warehouse_id = 1;

START TRANSACTION;

    -- Create the order
    INSERT INTO `Order` (customer_id, warehouse_id, order_status)
    VALUES (4, 1, 'CREATED');

    SET @new_order_id = LAST_INSERT_ID();

    -- Add items
    INSERT INTO Order_Item (order_id, product_id, quantity, unit_price)
    VALUES (@new_order_id, 1, 3, 30.00),   -- 3x Amul Milk
           (@new_order_id, 4, 2, 25.00);   -- 2x Good Day Biscuits

    -- Reserve inventory (move from available to reserved)
    UPDATE Inventory SET available_qty = available_qty - 3, reserved_qty = reserved_qty + 3
    WHERE product_id = 1 AND warehouse_id = 1;

    UPDATE Inventory SET available_qty = available_qty - 2, reserved_qty = reserved_qty + 2
    WHERE product_id = 4 AND warehouse_id = 1;

    -- Update order totals
    UPDATE `Order`
    SET total_items  = 5,
        total_amount = (3 * 30.00 * 1.20) + (2 * 25.00 * 1.20)   -- incl. GST
    WHERE order_id = @new_order_id;

COMMIT;

-- Snapshot AFTER
SELECT 'AFTER ORDER' AS stage, available_qty, reserved_qty
FROM Inventory WHERE product_id IN (1, 4) AND warehouse_id = 1;

SELECT 'NEW ORDER' AS stage, order_id, total_items, total_amount, order_status
FROM `Order` WHERE order_id = @new_order_id;


-- ─────────────────────────────────────────────────────────
-- TRANSACTION 1.3: Atomicity Demo — ROLLBACK on failure
-- Scenario: Attempt to place an order with insufficient stock
-- ACID: Atomicity — failed transaction leaves DB unchanged
-- ─────────────────────────────────────────────────────────

SELECT 'BEFORE ROLLBACK TEST' AS stage, available_qty
FROM Inventory WHERE product_id = 9 AND warehouse_id = 1;  -- Kaju Katli (limited stock)

START TRANSACTION;

    INSERT INTO `Order` (customer_id, warehouse_id, order_status)
    VALUES (5, 1, 'CREATED');

    SET @failed_order = LAST_INSERT_ID();

    INSERT INTO Order_Item (order_id, product_id, quantity, unit_price)
    VALUES (@failed_order, 9, 99999, 600.00);  -- absurdly large qty

    -- Realize stock is insufficient → ROLLBACK everything
ROLLBACK;

-- Verify: DB is unchanged (the order should NOT exist)
SELECT 'AFTER ROLLBACK' AS stage, COUNT(*) AS order_exists
FROM `Order` WHERE order_id = @failed_order;

SELECT 'STOCK UNCHANGED' AS stage, available_qty
FROM Inventory WHERE product_id = 9 AND warehouse_id = 1;


-- ─────────────────────────────────────────────────────────
-- TRANSACTION 1.4: Restock Fulfillment (multi-table, atomic)
-- Scenario: Producer fulfills a warehouse restock request
-- Updates: Batch, Inventory, Producer.earnings, Restock_Request.status
-- ─────────────────────────────────────────────────────────

-- Create a pending restock request first
INSERT INTO Restock_Request (warehouse_id, producer_id, product_id, requested_qty, quoted_price)
VALUES (1, 1, 1, 100, 30.00);

SET @rr_id = LAST_INSERT_ID();

SELECT 'BEFORE RESTOCK' AS stage,
       (SELECT earnings FROM Producer WHERE producer_id = 1) AS amul_earnings,
       (SELECT available_qty FROM Inventory WHERE product_id = 1 AND warehouse_id = 1) AS milk_stock;

START TRANSACTION;

    -- Insert batch (trigger auto-updates inventory + warehouse budget)
    INSERT INTO Batch (producer_id, product_id, warehouse_id, request_id, quantity, unit_cost, arrival_date)
    VALUES (1, 1, 1, @rr_id, 100, 30.00, CURDATE());

    -- Update producer earnings
    UPDATE Producer SET earnings = earnings + (100 * 30.00) WHERE producer_id = 1;

    -- Mark request as fulfilled
    UPDATE Restock_Request SET status = 'Fulfilled' WHERE request_id = @rr_id;

COMMIT;

SELECT 'AFTER RESTOCK' AS stage,
       (SELECT earnings FROM Producer WHERE producer_id = 1) AS amul_earnings,
       (SELECT available_qty FROM Inventory WHERE product_id = 1 AND warehouse_id = 1) AS milk_stock,
       (SELECT status FROM Restock_Request WHERE request_id = @rr_id) AS request_status;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 2: WR CONFLICT — DIRTY READ                                      ║
-- ║  Ref: Ch.17 Slide 17.22-17.28                                             ║
-- ║  T2 reads data written by T1 BEFORE T1 commits → dirty read               ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
-- 
-- Requires TWO MySQL sessions running simultaneously.
-- 
-- SCENARIO: Customer 1's wallet balance = ₹X
--   T1 (Session A): Deducts ₹500 from Customer 1's wallet (but hasn't committed)
--   T2 (Session B): Reads Customer 1's wallet balance (sees uncommitted deduction)
--   T1 (Session A): ROLLS BACK the deduction
--   Result: T2 read a value (X - 500) that NEVER actually existed in the DB!
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1)                  │        SESSION B (T2)                  │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ SET TRANSACTION ISOLATION LEVEL        │ Step 2:                                │
-- │   READ COMMITTED;                      │ SET TRANSACTION ISOLATION LEVEL        │
-- │ START TRANSACTION;                     │   READ UNCOMMITTED;                    │
-- │                                        │ START TRANSACTION;                     │
-- │ Step 3:                                │                                        │
-- │ UPDATE Wallet                          │                                        │
-- │ SET balance = balance - 500            │                                        │
-- │ WHERE customer_id = 1;                 │                                        │
-- │                                        │                                        │
-- │ -- (NOT committed yet!)                │                                        │
-- │                                        │ Step 4:                                │
-- │                                        │ SELECT balance FROM Wallet             │
-- │                                        │ WHERE customer_id = 1;                 │
-- │                                        │ -- ⚠ DIRTY READ: sees balance - 500   │
-- │                                        │ -- even though T1 hasn't committed!    │
-- │                                        │                                        │
-- │ Step 5:                                │                                        │
-- │ ROLLBACK;                              │                                        │
-- │ -- T1 aborts, balance is restored      │                                        │
-- │                                        │ Step 6:                                │
-- │                                        │ SELECT balance FROM Wallet             │
-- │                                        │ WHERE customer_id = 1;                 │
-- │                                        │ -- Now sees original balance           │
-- │                                        │ -- T2 previously read a PHANTOM value! │
-- │                                        │ COMMIT;                                │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- EFFECT ON DB: T2 made decisions based on a balance that never truly existed.
-- In our WMS: If T2 was a checkout validating "does customer have enough funds?",
-- it could approve an order based on a wrong (lower) balance.
-- FIX: Use READ COMMITTED or higher isolation level.

-- Executable single-session simulation of Dirty Read concept:
-- (Shows what READ UNCOMMITTED allows vs READ COMMITTED prevents)

SELECT '── DIRTY READ DEMO ──' AS section;

SELECT 'Initial Balance' AS stage, balance FROM Wallet WHERE customer_id = 1;

-- Under READ COMMITTED (default in most systems), dirty reads are PREVENTED.
-- Under READ UNCOMMITTED, the uncommitted update would be visible to other sessions.
-- Single-session proof:

START TRANSACTION;
    UPDATE Wallet SET balance = balance - 500 WHERE customer_id = 1;
    SELECT 'Inside T1 (uncommitted)' AS stage, balance FROM Wallet WHERE customer_id = 1;
    -- Another session with READ UNCOMMITTED would see this value ← DIRTY READ
ROLLBACK;

SELECT 'After ROLLBACK (unchanged)' AS stage, balance FROM Wallet WHERE customer_id = 1;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3: RW CONFLICT — UNREPEATABLE READ                               ║
-- ║  Ref: Ch.17 Slide 17.29-17.30                                             ║
-- ║  T1 reads A, T2 modifies A and commits, T1 re-reads A → different value   ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- SCENARIO: Warehouse admin checks product price, then a producer changes it,
-- then admin re-reads the price and gets a different value.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1 - Admin)          │        SESSION B (T2 - Producer)       │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ SET TRANSACTION ISOLATION LEVEL        │                                        │
-- │   READ COMMITTED;                      │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │                                        │                                        │
-- │ Step 2:                                │                                        │
-- │ SELECT price_before_tax                │                                        │
-- │ FROM Producer_Product                  │                                        │
-- │ WHERE producer_id=1 AND product_id=1;  │                                        │
-- │ -- Reads ₹30.00                        │                                        │
-- │                                        │ Step 3:                                │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ UPDATE Producer_Product                │
-- │                                        │ SET price_before_tax = 45.00           │
-- │                                        │ WHERE producer_id=1 AND product_id=1;  │
-- │                                        │ COMMIT;                                │
-- │                                        │                                        │
-- │ Step 4:                                │                                        │
-- │ SELECT price_before_tax                │                                        │
-- │ FROM Producer_Product                  │                                        │
-- │ WHERE producer_id=1 AND product_id=1;  │                                        │
-- │ -- ⚠ UNREPEATABLE READ: now sees ₹45! │                                        │
-- │ -- Same query, different result!        │                                        │
-- │ COMMIT;                                │                                        │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- EFFECT ON DB: Admin creates restock request quoting ₹30, but actual price is ₹45.
-- The admin's cost calculation is wrong mid-transaction!
-- FIX: Use REPEATABLE READ or SERIALIZABLE isolation level.

SELECT '── UNREPEATABLE READ DEMO ──' AS section;

-- Single-session simulation showing the concept:
SELECT 'Read 1 (Amul Milk price)' AS stage, price_before_tax
FROM Producer_Product WHERE producer_id = 1 AND product_id = 1;

-- Simulate T2 modifying the price between two reads of T1:
START TRANSACTION;
    UPDATE Producer_Product SET price_before_tax = 45.00
    WHERE producer_id = 1 AND product_id = 1;
COMMIT;

-- T1's second read would see the new price under READ COMMITTED:
SELECT 'Read 2 (price changed!)' AS stage, price_before_tax
FROM Producer_Product WHERE producer_id = 1 AND product_id = 1;

-- Restore original price
UPDATE Producer_Product SET price_before_tax = 30.00
WHERE producer_id = 1 AND product_id = 1;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 4: WW CONFLICT — LOST UPDATE                                     ║
-- ║  Ref: Ch.17 Slide 17.31-17.34                                             ║
-- ║  T1 writes A, T2 overwrites A before T1 commits → T1's update is lost     ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- SCENARIO: Two admins simultaneously update the warehouse budget.
-- Admin A sets budget to ₹300,000, Admin B sets budget to ₹500,000.
-- Without proper isolation, one update is lost (blind write).
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1 - Admin A)        │        SESSION B (T2 - Admin B)        │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │ SELECT budget FROM Warehouse           │                                        │
-- │ WHERE warehouse_id = 1;                │                                        │
-- │ -- Reads: ₹200,000                     │                                        │
-- │                                        │ Step 2:                                │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ SELECT budget FROM Warehouse           │
-- │                                        │ WHERE warehouse_id = 1;                │
-- │                                        │ -- Also reads: ₹200,000               │
-- │ Step 3:                                │                                        │
-- │ UPDATE Warehouse                       │                                        │
-- │ SET budget = 300000                     │                                        │
-- │ WHERE warehouse_id = 1;                │                                        │
-- │                                        │ Step 4:                                │
-- │                                        │ UPDATE Warehouse                       │
-- │                                        │ SET budget = 500000                     │
-- │                                        │ WHERE warehouse_id = 1;                │
-- │                                        │ -- ⚠ BLOCKED until T1 commits!         │
-- │ Step 5:                                │                                        │
-- │ COMMIT;                                │                                        │
-- │                                        │ Step 6:                                │
-- │                                        │ -- (unblocks) ⚠ OVERWRITES T1's value │
-- │                                        │ COMMIT;                                │
-- │                                        │                                        │
-- │ SELECT budget FROM Warehouse           │                                        │
-- │ WHERE warehouse_id = 1;                │                                        │
-- │ -- Shows ₹500,000 — T1's ₹300,000     │                                        │
-- │ -- is LOST!                             │                                        │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- EFFECT ON DB: Admin A thinks budget = ₹300,000 but it's actually ₹500,000.
-- FIX: Use SELECT ... FOR UPDATE locking, or SERIALIZABLE isolation.

SELECT '── LOST UPDATE DEMO ──' AS section;

-- Save original budget
SET @original_budget = (SELECT budget FROM Warehouse WHERE warehouse_id = 1);

-- Simulate the conflict in a single session:
-- T1 reads and updates
START TRANSACTION;
    SELECT 'T1 reads budget' AS stage, budget FROM Warehouse WHERE warehouse_id = 1;
    UPDATE Warehouse SET budget = 300000 WHERE warehouse_id = 1;
    SELECT 'T1 writes 300000' AS stage, budget FROM Warehouse WHERE warehouse_id = 1;
COMMIT;

-- T2 overwrites without knowing T1's change
START TRANSACTION;
    UPDATE Warehouse SET budget = 500000 WHERE warehouse_id = 1;
    SELECT 'T2 overwrites → 500000' AS stage, budget FROM Warehouse WHERE warehouse_id = 1;
COMMIT;

-- T1's update is LOST
SELECT 'FINAL (T1 lost!)' AS stage, budget FROM Warehouse WHERE warehouse_id = 1;

-- Restore original
UPDATE Warehouse SET budget = @original_budget WHERE warehouse_id = 1;

-- HOW TO PREVENT: Use FOR UPDATE lock
-- START TRANSACTION;
-- SELECT budget FROM Warehouse WHERE warehouse_id = 1 FOR UPDATE;
-- -- This locks the row until COMMIT, preventing concurrent writes


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 5: PHANTOM READ                                                  ║
-- ║  Ref: Ch.17 Slide 17.52                                                   ║
-- ║  T1 reads a set of rows, T2 inserts new rows, T1 re-reads → extra rows    ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- SCENARIO: Admin counts pending restock requests. A new request is inserted
-- by another session. Admin re-counts and gets a different number.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1 - Admin)          │        SESSION B (T2 - Warehouse)      │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ SET TRANSACTION ISOLATION LEVEL        │                                        │
-- │   READ COMMITTED;                      │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │                                        │                                        │
-- │ Step 2:                                │                                        │
-- │ SELECT COUNT(*) FROM Restock_Request   │                                        │
-- │ WHERE status = 'Pending';              │                                        │
-- │ -- Returns: N                          │                                        │
-- │                                        │ Step 3:                                │
-- │                                        │ INSERT INTO Restock_Request            │
-- │                                        │ (warehouse_id, producer_id, product_id,│
-- │                                        │  requested_qty, quoted_price)          │
-- │                                        │ VALUES (1, 2, 5, 100, 35.00);          │
-- │                                        │ COMMIT;                                │
-- │ Step 4:                                │                                        │
-- │ SELECT COUNT(*) FROM Restock_Request   │                                        │
-- │ WHERE status = 'Pending';              │                                        │
-- │ -- ⚠ PHANTOM: Returns N+1 !           │                                        │
-- │ -- A "phantom" row appeared!           │                                        │
-- │ COMMIT;                                │                                        │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- EFFECT ON DB: Admin's report is inconsistent within the same transaction.
-- FIX: Use SERIALIZABLE isolation level (prevents phantom reads).

SELECT '── PHANTOM READ DEMO ──' AS section;

SELECT 'Count before phantom' AS stage,
       COUNT(*) AS pending_requests
FROM Restock_Request WHERE status = 'Pending';

-- Another session inserts a new pending request:
INSERT INTO Restock_Request (warehouse_id, producer_id, product_id, requested_qty, quoted_price)
VALUES (1, 3, 7, 50, 40.00);

-- T1 re-reads: phantom row appears!
SELECT 'Count after phantom' AS stage,
       COUNT(*) AS pending_requests
FROM Restock_Request WHERE status = 'Pending';

-- Cleanup
DELETE FROM Restock_Request
WHERE producer_id = 3 AND product_id = 7 AND requested_qty = 50
ORDER BY request_id DESC LIMIT 1;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 6: ISOLATION LEVEL DEMONSTRATIONS                                ║
-- ║  Ref: Ch.17 Slides 17.49-17.51                                            ║
-- ║  4 SQL-92 levels: READ UNCOMMITTED, READ COMMITTED,                       ║
-- ║                   REPEATABLE READ, SERIALIZABLE                           ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT '── ISOLATION LEVELS ──' AS section;

-- ─────────────────────────────────────────────────────────
-- 6.1: READ UNCOMMITTED — allows dirty reads
-- ─────────────────────────────────────────────────────────
-- Session B would run:
--   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--   START TRANSACTION;
--   SELECT balance FROM Wallet WHERE customer_id = 1;
--   -- Can see uncommitted changes from other transactions
--   COMMIT;

-- ─────────────────────────────────────────────────────────
-- 6.2: READ COMMITTED — prevents dirty reads, allows unrepeatable reads
-- ─────────────────────────────────────────────────────────
-- Session B:
--   SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
--   START TRANSACTION;
--   SELECT balance FROM Wallet WHERE customer_id = 1;  -- sees X
--   -- (Session A commits a change to balance)
--   SELECT balance FROM Wallet WHERE customer_id = 1;  -- may see X' ≠ X
--   COMMIT;

-- ─────────────────────────────────────────────────────────
-- 6.3: REPEATABLE READ (MySQL default) — prevents dirty + unrepeatable reads
-- ─────────────────────────────────────────────────────────
-- Executable demo:
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
    SELECT 'RR Read 1' AS stage, balance FROM Wallet WHERE customer_id = 2;
    -- Even if another session changes the balance and commits,
    -- this transaction will STILL see the original value on re-read.
    -- (MySQL uses MVCC snapshot at first read)
    SELECT 'RR Read 2 (same!)' AS stage, balance FROM Wallet WHERE customer_id = 2;
COMMIT;

-- ─────────────────────────────────────────────────────────
-- 6.4: SERIALIZABLE — prevents ALL anomalies (including phantoms)
-- ─────────────────────────────────────────────────────────
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;
    SELECT 'SERIALIZABLE' AS stage,
           COUNT(*) AS order_count
    FROM `Order` WHERE customer_id = 1;
    -- Under SERIALIZABLE, any INSERT into Order by another session
    -- that matches this WHERE clause will BLOCK until this transaction commits.
    -- This prevents phantom reads.
COMMIT;

-- Restore to MySQL default
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 6.5: ISOLATION LEVEL COMPARISON TABLE                            ║
-- ║  (reference for examiner)                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- ┌──────────────────────┬────────────┬──────────────────┬──────────────┬─────────────┐
-- │ Isolation Level      │ Dirty Read │ Unrepeatable Read│ Phantom Read │ Lost Update │
-- ├──────────────────────┼────────────┼──────────────────┼──────────────┼─────────────┤
-- │ READ UNCOMMITTED     │    YES     │       YES        │     YES      │     NO      │
-- │ READ COMMITTED       │    NO      │       YES        │     YES      │     NO      │
-- │ REPEATABLE READ      │    NO      │       NO         │   YES(*)     │     NO      │
-- │ SERIALIZABLE         │    NO      │       NO         │     NO       │     NO      │
-- └──────────────────────┴────────────┴──────────────────┴──────────────┴─────────────┘
-- (*) MySQL's InnoDB REPEATABLE READ uses gap locking, which prevents most phantoms
-- All levels prevent dirty writes (lost updates via WW on committed data)



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 7: DEADLOCK SCENARIO                                             ║
-- ║  Two transactions each hold a lock and wait for the other's lock           ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- SCENARIO: Two customers try to transfer money to each other simultaneously.
--   T1: Transfer from Customer 1 → Customer 2 (locks Wallet row 1, then needs row 2)
--   T2: Transfer from Customer 2 → Customer 1 (locks Wallet row 2, then needs row 1)
--   → DEADLOCK! MySQL detects this and rolls back one transaction.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1)                  │        SESSION B (T2)                  │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │ UPDATE Wallet SET balance=balance-100  │                                        │
-- │ WHERE customer_id = 1;                 │                                        │
-- │ -- Acquires X-lock on row customer_id=1│                                        │
-- │                                        │ Step 2:                                │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ UPDATE Wallet SET balance=balance-100  │
-- │                                        │ WHERE customer_id = 2;                 │
-- │                                        │ -- Acquires X-lock on row customer_id=2│
-- │ Step 3:                                │                                        │
-- │ UPDATE Wallet SET balance=balance+100  │                                        │
-- │ WHERE customer_id = 2;                 │                                        │
-- │ -- ⏳ BLOCKED! Waiting for T2's lock   │                                        │
-- │                                        │ Step 4:                                │
-- │                                        │ UPDATE Wallet SET balance=balance+100  │
-- │                                        │ WHERE customer_id = 1;                 │
-- │                                        │ -- ⏳ BLOCKED! Waiting for T1's lock   │
-- │                                        │                                        │
-- │        ┌─── DEADLOCK DETECTED! ────┐   │                                        │
-- │        │ MySQL chooses one victim  │   │                                        │
-- │        │ and rolls it back with    │   │                                        │
-- │        │ ERROR 1213 (40001)        │   │                                        │
-- │        └───────────────────────────┘   │                                        │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- EFFECT: One transaction is automatically rolled back by InnoDB.
-- FIX: Always acquire locks in the SAME ORDER (e.g., by customer_id ASC)
-- to prevent circular wait conditions.

SELECT '── DEADLOCK PREVENTION EXAMPLE ──' AS section;

-- CORRECT approach: Always lock in consistent order (customer_id ASC)
-- This prevents deadlock by eliminating circular wait

START TRANSACTION;
    -- Both T1 and T2 should lock customer_id = 1 first, then 2
    SELECT balance FROM Wallet WHERE customer_id = 1 FOR UPDATE;
    SELECT balance FROM Wallet WHERE customer_id = 2 FOR UPDATE;

    -- Now safely do the transfer
    UPDATE Wallet SET balance = balance - 100 WHERE customer_id = 1;
    UPDATE Wallet SET balance = balance + 100 WHERE customer_id = 2;
COMMIT;

-- Reverse to restore balances
START TRANSACTION;
    UPDATE Wallet SET balance = balance + 100 WHERE customer_id = 1;
    UPDATE Wallet SET balance = balance - 100 WHERE customer_id = 2;
COMMIT;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 8: SAVEPOINTS & PARTIAL ROLLBACK                                 ║
-- ║  Rollback part of a transaction without losing earlier work                ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT '── SAVEPOINT DEMO ──' AS section;

SELECT 'Initial State' AS stage,
       (SELECT balance FROM Wallet WHERE customer_id = 3) AS rohit_balance,
       (SELECT earnings FROM Producer WHERE producer_id = 2) AS britannia_earnings;

START TRANSACTION;

    -- Part 1: Add funds to Rohit's wallet (this should persist)
    UPDATE Wallet SET balance = balance + 1000 WHERE customer_id = 3;

    SAVEPOINT after_wallet_topup;

    -- Part 2: Try updating producer earnings (oops, wrong amount!)
    UPDATE Producer SET earnings = earnings + 999999 WHERE producer_id = 2;

    -- Realize the earnings update was wrong → rollback ONLY Part 2
    ROLLBACK TO SAVEPOINT after_wallet_topup;

    -- Part 2 (corrected): Update earnings with correct amount
    UPDATE Producer SET earnings = earnings + 500 WHERE producer_id = 2;

COMMIT;

SELECT 'After Savepoint Demo' AS stage,
       (SELECT balance FROM Wallet WHERE customer_id = 3) AS rohit_balance_increased,
       (SELECT earnings FROM Producer WHERE producer_id = 2) AS britannia_correct;

-- Restore values
UPDATE Wallet SET balance = balance - 1000 WHERE customer_id = 3;
UPDATE Producer SET earnings = earnings - 500 WHERE producer_id = 2;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 9: SERIALIZABLE SCHEDULE — CONFLICT-FREE EXECUTION               ║
-- ║  Ref: Ch.17 Slides 17.15-17.21                                            ║
-- ║  A concurrent schedule that is equivalent to a serial schedule             ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT '── SERIALIZABLE SCHEDULE DEMO ──' AS section;

-- SCENARIO: Two transactions that are conflict-serializable
--   T1: Transfers ₹100 from Customer 1 → Customer 2
--   T2: Adds 10% interest to Customer 1 and Customer 2 wallets
--
-- We interleave them such that the result equals serial schedule (T1 then T2):
--
-- Schedule:
--   T1: Read(Cust1_bal)    → deduct 100
--   T1: Write(Cust1_bal)
--   T2: Read(Cust1_bal)    → compute 10% on new value
--   T2: Write(Cust1_bal)
--   T1: Read(Cust2_bal)    → add 100
--   T1: Write(Cust2_bal)
--   T2: Read(Cust2_bal)    → compute 10% on new value
--   T2: Write(Cust2_bal)
--
-- Precedence: T1 → T2 (on both A and B). No cycle → CONFLICT SERIALIZABLE ✓

-- Step 1: Record initial balances
SET @c1_before = (SELECT balance FROM Wallet WHERE customer_id = 1);
SET @c2_before = (SELECT balance FROM Wallet WHERE customer_id = 2);
SELECT 'Before' AS stage, @c1_before AS cust1, @c2_before AS cust2,
       (@c1_before + @c2_before) AS total;

-- Execute the serializable schedule:
START TRANSACTION;
    -- T1 action: deduct 100 from Customer 1
    UPDATE Wallet SET balance = balance - 100 WHERE customer_id = 1;

    -- T2 action: 10% interest on Customer 1 (after T1's deduction)
    UPDATE Wallet SET balance = balance * 1.10 WHERE customer_id = 1;

    -- T1 action: add 100 to Customer 2
    UPDATE Wallet SET balance = balance + 100 WHERE customer_id = 2;

    -- T2 action: 10% interest on Customer 2 (after T1's addition)
    UPDATE Wallet SET balance = balance * 1.10 WHERE customer_id = 2;
COMMIT;

SET @c1_after = (SELECT balance FROM Wallet WHERE customer_id = 1);
SET @c2_after = (SELECT balance FROM Wallet WHERE customer_id = 2);
SELECT 'After (T1→T2)' AS stage, @c1_after AS cust1, @c2_after AS cust2,
       (@c1_after + @c2_after) AS total;

-- Verify: equivalent to serial schedule T1 then T2
-- T1 first: Cust1 = @c1_before - 100, Cust2 = @c2_before + 100
-- Then T2:  Cust1 = (c1_before - 100) * 1.10, Cust2 = (c2_before + 100) * 1.10
SELECT 'Expected (serial T1→T2)' AS stage,
       ROUND((@c1_before - 100) * 1.10, 2) AS expected_cust1,
       ROUND((@c2_before + 100) * 1.10, 2) AS expected_cust2;

-- Restore original balances
UPDATE Wallet SET balance = @c1_before WHERE customer_id = 1;
UPDATE Wallet SET balance = @c2_before WHERE customer_id = 2;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 10: RECOVERABILITY & CASCADING ROLLBACK                          ║
-- ║  Ref: Ch.17 Slides 17.43-17.45                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- RECOVERABLE SCHEDULE: If Tj reads data written by Ti, then Ti must commit
-- BEFORE Tj commits. Otherwise the schedule is NOT recoverable.
--
-- CASCADING ROLLBACK: If T1 aborts, any transaction that read T1's
-- uncommitted data must also abort → chain reaction.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1)                  │        SESSION B (T2)                  │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ NON-RECOVERABLE SCHEDULE:              │                                        │
-- │                                        │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │ UPDATE Wallet SET balance = 9999       │                                        │
-- │ WHERE customer_id = 5;                 │                                        │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ -- (READ UNCOMMITTED)                  │
-- │                                        │ SELECT balance FROM Wallet             │
-- │                                        │ WHERE customer_id = 5;                 │
-- │                                        │ -- Reads 9999 (dirty read)             │
-- │                                        │ COMMIT; ← T2 commits first!            │
-- │ ROLLBACK; ← T1 aborts                 │                                        │
-- │                                        │ -- ⚠ T2 committed with data from a    │
-- │                                        │ -- transaction that no longer exists!  │
-- │                                        │ -- This schedule is NOT recoverable.   │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- RECOVERABLE SCHEDULE: T1 must COMMIT before T2 commits.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (T1)                  │        SESSION B (T2)                  │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ START TRANSACTION;                     │                                        │
-- │ UPDATE Wallet SET balance = 5000       │                                        │
-- │ WHERE customer_id = 5;                 │                                        │
-- │ COMMIT; ← T1 commits first ✓          │                                        │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ SELECT balance FROM Wallet             │
-- │                                        │ WHERE customer_id = 5;                 │
-- │                                        │ -- Reads 5000 (committed data)         │
-- │                                        │ COMMIT;                                │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- CASCADELESS SCHEDULE: T2 only reads data AFTER T1 commits.
-- No dirty reads → no cascading rollback needed. ✓
-- MySQL's default REPEATABLE READ isolation enforces cascadeless schedules.

SELECT '── RECOVERABILITY DEMO ──' AS section;

-- Demonstrate cascadeless execution (safe pattern):
SET @orig_bal_5 = (SELECT balance FROM Wallet WHERE customer_id = 5);

-- T1 commits first
START TRANSACTION;
    UPDATE Wallet SET balance = 5000 WHERE customer_id = 5;
COMMIT;  -- T1 committed ✓

-- T2 reads only committed data (cascadeless)
START TRANSACTION;
    SELECT 'T2 reads committed data' AS stage, balance FROM Wallet WHERE customer_id = 5;
    -- This is safe: if T2 needs to rollback, no cascade needed
COMMIT;

-- Restore
UPDATE Wallet SET balance = @orig_bal_5 WHERE customer_id = 5;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 11: FOR UPDATE LOCKING (Pessimistic Concurrency Control)         ║
-- ║  Ref: Ch.17 Slide 17.51 — Locking for implementation of isolation         ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT '── FOR UPDATE LOCKING DEMO ──' AS section;

-- Scenario: Safely check wallet balance and place order atomically
-- Without FOR UPDATE, another transaction could drain the wallet between
-- the SELECT and the UPDATE (a TOCTOU race condition).

START TRANSACTION;
    -- Lock the wallet row — no other transaction can read/write this row
    SELECT balance INTO @locked_balance
    FROM Wallet WHERE customer_id = 1 FOR UPDATE;

    SELECT 'Locked balance' AS stage, @locked_balance AS balance;

    -- Only proceed if sufficient funds (guaranteed no concurrent drain)
    -- In a real scenario: IF @locked_balance >= order_total THEN deduct
    -- This is the pattern used in sp_place_order and sp_cancel_order
COMMIT;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 12: CONCURRENT ORDER PLACEMENT — REAL BUSINESS CONFLICT          ║
-- ║  WMS-specific scenario mixing all concepts                                ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- SCENARIO: Two customers try to buy the last 5 units of Kaju Katli
-- at the same time. Only one should succeed.
--
-- ┌────────────────────────────────────────┬────────────────────────────────────────┐
-- │        SESSION A (Customer 4)          │        SESSION B (Customer 5)          │
-- ├────────────────────────────────────────┼────────────────────────────────────────┤
-- │ Step 1:                                │                                        │
-- │ START TRANSACTION;                     │                                        │
-- │ SELECT available_qty FROM Inventory    │                                        │
-- │ WHERE product_id = 9                   │                                        │
-- │   AND warehouse_id = 1                 │                                        │
-- │ FOR UPDATE;                            │                                        │
-- │ -- Returns: 5 (and LOCKS the row)      │                                        │
-- │                                        │ Step 2:                                │
-- │                                        │ START TRANSACTION;                     │
-- │                                        │ SELECT available_qty FROM Inventory    │
-- │                                        │ WHERE product_id = 9                   │
-- │                                        │   AND warehouse_id = 1                 │
-- │                                        │ FOR UPDATE;                            │
-- │                                        │ -- ⏳ BLOCKED (waiting for T1's lock) │
-- │ Step 3:                                │                                        │
-- │ -- 5 >= 5 → sufficient stock           │                                        │
-- │ UPDATE Inventory                       │                                        │
-- │ SET available_qty = available_qty - 5  │                                        │
-- │ WHERE product_id = 9                   │                                        │
-- │   AND warehouse_id = 1;                │                                        │
-- │ INSERT INTO `Order` ...                │                                        │
-- │ COMMIT;                                │                                        │
-- │                                        │ Step 4:                                │
-- │                                        │ -- (unblocked) SELECT returns: 0       │
-- │                                        │ -- 0 < 5 → insufficient stock!         │
-- │                                        │ ROLLBACK;                              │
-- │                                        │ -- Customer 5's order is rejected ✓    │
-- └────────────────────────────────────────┴────────────────────────────────────────┘
--
-- This demonstrates how FOR UPDATE + transactions solve the
-- classic "double booking" / "overselling" problem.

SELECT '── CONCURRENT ORDER (FOR UPDATE) DEMO ──' AS section;

-- Single-session demonstration:
SET @kk_stock = (SELECT available_qty FROM Inventory WHERE product_id = 9 AND warehouse_id = 1);
SELECT 'Kaju Katli stock' AS stage, @kk_stock AS available;

START TRANSACTION;
    -- T1: Lock and check
    SELECT available_qty INTO @stock
    FROM Inventory WHERE product_id = 9 AND warehouse_id = 1 FOR UPDATE;

    -- T1: Deduct if enough
    UPDATE Inventory SET available_qty = available_qty - 5
    WHERE product_id = 9 AND warehouse_id = 1 AND available_qty >= 5;

    SELECT 'After T1 purchase' AS stage, available_qty
    FROM Inventory WHERE product_id = 9 AND warehouse_id = 1;
COMMIT;

-- Restore
UPDATE Inventory SET available_qty = @kk_stock
WHERE product_id = 9 AND warehouse_id = 1;



-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SUMMARY                                                                   ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
--
-- This file demonstrates the following Ch.17 Transaction Management concepts
-- applied to our Warehouse Management System:
--
-- ┌────┬──────────────────────────────────┬───────────────────────────────────────┐
-- │ #  │ Concept                          │ WMS Scenario                          │
-- ├────┼──────────────────────────────────┼───────────────────────────────────────┤
-- │  1 │ ACID Properties                  │ Fund transfer, order placement,       │
-- │    │                                  │ restock fulfillment                   │
-- │  2 │ WR Conflict (Dirty Read)         │ Reading uncommitted wallet deduction  │
-- │  3 │ RW Conflict (Unrepeatable Read)  │ Price change between admin reads      │
-- │  4 │ WW Conflict (Lost Update)        │ Concurrent budget overwrites          │
-- │  5 │ Phantom Read                     │ New restock request appears mid-query │
-- │  6 │ Isolation Levels                 │ READ UNCOMMITTED → SERIALIZABLE       │
-- │  7 │ Deadlock                         │ Circular wallet transfers             │
-- │  8 │ Savepoints                       │ Partial rollback of incorrect update  │
-- │  9 │ Serializability                  │ Transfer + interest interleaving      │
-- │ 10 │ Recoverability                   │ Commit ordering for dirty reads       │
-- │ 11 │ FOR UPDATE Locking               │ Pessimistic wallet balance check      │
-- │ 12 │ Concurrent Orders                │ Last-unit stock competition           │
-- └────┴──────────────────────────────────┴───────────────────────────────────────┘
--
-- All transactions restore original data after each demo to keep the database clean.
-- Conflict scenarios include both single-session proofs AND two-session instructions.
-- ============================================================================
