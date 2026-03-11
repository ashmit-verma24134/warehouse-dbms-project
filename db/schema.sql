CREATE DATABASE IF NOT EXISTS supplychain_db;
USE supplychain_db;

-- Drop table and views solely for debugging purpose so that we can rerun schema without overwriting previous schemas 
DROP VIEW IF EXISTS v_warehouse_financial_dashboard;
DROP VIEW IF EXISTS v_warehouse_profit;
DROP VIEW IF EXISTS v_warehouse_cost;
DROP VIEW IF EXISTS v_warehouse_revenue;
DROP VIEW IF EXISTS v_warehouse_summary;
DROP VIEW IF EXISTS v_low_stock_products;
DROP VIEW IF EXISTS v_staff_inventory;
DROP VIEW IF EXISTS v_customer_products;
DROP VIEW IF EXISTS v_order_total;
DROP VIEW IF EXISTS v_inventory_stock;

DROP TABLE IF EXISTS Reorder_Config;
DROP TABLE IF EXISTS Order_Item;
DROP TABLE IF EXISTS `Order`;
DROP TABLE IF EXISTS Inventory;
DROP TABLE IF EXISTS Batch;
DROP TABLE IF EXISTS Wallet;
DROP TABLE IF EXISTS Customer;
DROP TABLE IF EXISTS Admin;
DROP TABLE IF EXISTS Warehouse;
DROP TABLE IF EXISTS Producer_Product;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Producer;

-- ==============================
-- PRODUCER TABLE
-- ==============================
CREATE TABLE Producer (
    producer_id INT AUTO_INCREMENT PRIMARY KEY,
    producer_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    email VARCHAR(100) NOT NULL,
    approval_status ENUM('Pending','Approved','Rejected')
        NOT NULL DEFAULT 'Pending'
) ENGINE=InnoDB;

-- Run this once in your MySQL Workbench
ALTER TABLE Producer ADD COLUMN earnings DECIMAL(12,2) DEFAULT 0.00;

-- ==============================
-- PRODUCT TABLE
-- (Product type only)
-- ==============================
CREATE TABLE Product (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50),

    -- If you keep UNIQUE, only one "Atta" can exist
    INDEX idx_product_name (product_name)
) ENGINE=InnoDB;


-- ==============================
-- PRODUCER_PRODUCT (SUPPLIES)
-- M:N Relationship Table
-- ==============================
CREATE TABLE Producer_Product (
    producer_id INT NOT NULL,
    product_id  INT NOT NULL,

    -- Relationship attributes
    price_before_tax DECIMAL(10,2) NOT NULL,
    max_batch_limit  INT NOT NULL,

    PRIMARY KEY (producer_id, product_id),

    FOREIGN KEY (producer_id)
        REFERENCES Producer(producer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    FOREIGN KEY (product_id)
        REFERENCES Product(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CHECK (price_before_tax > 0),
    CHECK (max_batch_limit > 0)
) ENGINE=InnoDB;


-- Optional indexes (composite PK already indexed)
CREATE INDEX idx_pp_producer ON Producer_Product(producer_id);
CREATE INDEX idx_pp_product  ON Producer_Product(product_id);




-- Warehouse Table
CREATE TABLE Warehouse (
    warehouse_id INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_name VARCHAR(100) NOT NULL,

    total_capacity INT NOT NULL,
    used_capacity INT NOT NULL,

    -- NEW FIELD
    budget DECIMAL(12,2) NOT NULL,

    CONSTRAINT chk_total_capacity CHECK (total_capacity > 0),
    CONSTRAINT chk_used_capacity_nonneg CHECK (used_capacity >= 0),
    CONSTRAINT chk_used_le_total CHECK (used_capacity <= total_capacity),
    CONSTRAINT chk_budget_nonneg CHECK (budget >= 0)
) ENGINE=InnoDB;



-- Admin Table (1:1 with Warehouse)
CREATE TABLE Admin (
    admin_id INT AUTO_INCREMENT PRIMARY KEY,
    admin_name VARCHAR(100) NOT NULL,
    warehouse_id INT NOT NULL UNIQUE, -- No two admins can reference the same warehouse 
    CONSTRAINT fk_admin_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES Warehouse(warehouse_id)
        ON DELETE CASCADE
)ENGINE=InnoDB;

-- Batch Table
CREATE TABLE Batch (
    batch_id INT AUTO_INCREMENT PRIMARY KEY,

    producer_id INT NOT NULL,
    product_id INT NOT NULL,
    warehouse_id INT NOT NULL,

    quantity INT NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,
    arrival_date DATE NOT NULL,

    CONSTRAINT chk_batch_quantity CHECK (quantity > 0),
    CONSTRAINT chk_batch_unit_cost CHECK (unit_cost > 0),

    CONSTRAINT fk_batch_producer
        FOREIGN KEY (producer_id) REFERENCES Producer(producer_id),

    CONSTRAINT fk_batch_product
        FOREIGN KEY (product_id) REFERENCES Product(product_id),

    CONSTRAINT fk_batch_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id)
)ENGINE=InnoDB;
-- Run this to allow tracking of the request in the batch
ALTER TABLE Batch 
ADD COLUMN request_id INT NULL,
ADD CONSTRAINT fk_batch_request 
    FOREIGN KEY (request_id) REFERENCES Restock_Request(request_id);

-- Customer Table
CREATE TABLE Customer (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,

    -- Composite attribute
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,

    email VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;




-- Wallet Table (1-to-1 with Customer)
CREATE TABLE Wallet (
    wallet_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL UNIQUE,
    balance DECIMAL(10,2) NOT NULL,

    CONSTRAINT chk_balance_nonneg
        CHECK (balance >= 0),

    CONSTRAINT fk_wallet_customer
        FOREIGN KEY (customer_id)
        REFERENCES Customer(customer_id)
        ON DELETE CASCADE
)ENGINE=InnoDB;

CREATE TABLE `Order` (
    order_id INT AUTO_INCREMENT PRIMARY KEY,

    customer_id INT NOT NULL,
    warehouse_id INT NOT NULL,

    order_status ENUM(
        'CREATED',
        'CONFIRMED',
        'FAILED',
        'DISPATCHED',
        'DELIVERED'
    ) NOT NULL DEFAULT 'CREATED',

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Derived totals maintained by triggers
    total_items INT NOT NULL DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,

    -- Foreign keys
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES Customer(customer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_order_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES Warehouse(warehouse_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- Helpful indexes for query performance
    INDEX idx_order_customer (customer_id),
    INDEX idx_order_warehouse (warehouse_id),
    INDEX idx_order_status (order_status)
) ENGINE=InnoDB;

CREATE INDEX idx_order_created 
ON `Order`(created_at);
-- Order Item Table
-- Order Item Table
CREATE TABLE Order_Item (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,

    order_id INT NOT NULL,
    product_id INT NOT NULL,

    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    -- Derived attribute (20% tax)
    unit_price_with_tax DECIMAL(10,2)
        GENERATED ALWAYS AS (unit_price * 1.20) STORED,

    -- Prevent duplicate product per order
    CONSTRAINT uq_order_product UNIQUE (order_id, product_id),

    -- Domain constraints
    CONSTRAINT chk_order_item_qty CHECK (quantity > 0),
    CONSTRAINT chk_order_item_price CHECK (unit_price > 0),

    -- Foreign keys
    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id)
        REFERENCES `Order`(order_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_order_item_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB;



CREATE VIEW v_order_total AS
SELECT
    order_id,
    SUM(quantity * unit_price_with_tax) AS order_total_with_tax
FROM Order_Item
GROUP BY order_id;



-- Inventory Table (Current state of stock )
CREATE TABLE Inventory (
    inventory_id INT AUTO_INCREMENT PRIMARY KEY,

    warehouse_id INT NOT NULL,
    product_id INT NOT NULL,

    available_qty INT NOT NULL DEFAULT 0,
    reserved_qty INT NOT NULL DEFAULT 0,

    CONSTRAINT chk_inventory_available CHECK (available_qty >= 0),
    CONSTRAINT chk_inventory_reserved CHECK (reserved_qty >= 0),

    CONSTRAINT uq_inventory UNIQUE (warehouse_id, product_id),

    CONSTRAINT fk_inventory_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id),

    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id) REFERENCES Product(product_id)
) ENGINE=InnoDB;



CREATE INDEX idx_inventory_product 
ON Inventory(product_id);

CREATE INDEX idx_inventory_warehouse 
ON Inventory(warehouse_id);

CREATE VIEW v_inventory_stock AS
SELECT
    inventory_id,
    warehouse_id,
    product_id,
    available_qty,
    reserved_qty,
    (available_qty + reserved_qty) AS current_stock
FROM Inventory;


-- Reorder Configuration Table on minm threshold order again 
CREATE TABLE Reorder_Config (
    product_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    min_threshold INT NOT NULL,

    CONSTRAINT chk_min_threshold
        CHECK (min_threshold > 0),

    CONSTRAINT uq_reorder UNIQUE (product_id, warehouse_id),

    CONSTRAINT fk_reorder_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id),

    CONSTRAINT fk_reorder_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES Warehouse(warehouse_id)
) ENGINE=InnoDB;



USE supplychain_db;

-- 1. Ensure the table is dropped safely
DROP TABLE IF EXISTS Restock_Request;

-- 2. Create the table explicitly
CREATE TABLE Restock_Request (
    request_id INT AUTO_INCREMENT PRIMARY KEY,
    warehouse_id INT NOT NULL,
    producer_id INT NOT NULL,
    product_id INT NOT NULL,
    requested_qty INT NOT NULL,
    status ENUM('Pending', 'Fulfilled', 'Cancelled') DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse(warehouse_id),
    FOREIGN KEY (producer_id) REFERENCES Producer(producer_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id),
    CHECK (requested_qty > 0)
) ENGINE=InnoDB;

-- Trigger:Update Inventory & Enforce Capacity
-- Whenever a new batch arrives, this trigger checks warehouse capacity and updates inventory automatically.
DELIMITER $$

CREATE TRIGGER trg_before_batch_insert
BEFORE INSERT ON Batch
FOR EACH ROW
BEGIN
    DECLARE current_used INT;
    DECLARE total_cap INT;

    DECLARE purchase_cost DECIMAL(12,2);
    DECLARE warehouse_budget DECIMAL(12,2);

    -- NEW VARIABLE
    DECLARE prod_status VARCHAR(20);

    -- Check if producer is approved
    SELECT approval_status
    INTO prod_status
    FROM Producer
    WHERE producer_id = NEW.producer_id;

    IF prod_status <> 'Approved' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Producer not approved';
    END IF;

    -- Get warehouse capacity
    SELECT used_capacity, total_capacity
    INTO current_used, total_cap
    FROM Warehouse
    WHERE warehouse_id = NEW.warehouse_id;

    IF current_used + NEW.quantity < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid capacity calculation';
    END IF;

    -- Check capacity
    IF current_used + NEW.quantity > total_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse capacity exceeded';
    END IF;

    -- Calculate purchase cost
    SET purchase_cost = NEW.quantity * NEW.unit_cost;

    -- Get warehouse budget
    SELECT budget
    INTO warehouse_budget
    FROM Warehouse
    WHERE warehouse_id = NEW.warehouse_id;

    -- Check warehouse budget
    IF warehouse_budget < purchase_cost THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse budget exceeded';
    END IF;

    -- Update inventory
    INSERT INTO Inventory (warehouse_id, product_id, available_qty, reserved_qty)
    VALUES (NEW.warehouse_id, NEW.product_id, NEW.quantity, 0)
    ON DUPLICATE KEY UPDATE
        available_qty = available_qty + NEW.quantity;

    -- Update warehouse capacity and budget
    UPDATE Warehouse
    SET 
        used_capacity = used_capacity + NEW.quantity,
        budget = budget - purchase_cost
    WHERE warehouse_id = NEW.warehouse_id;

END$$

DELIMITER ;


-- Trigger:Reserve Inventory on Order Item
DELIMITER $$

CREATE TRIGGER trg_before_order_item_insert
BEFORE INSERT ON Order_Item
FOR EACH ROW
BEGIN
    DECLARE avail INT;
    DECLARE wh_id INT;

    -- Get warehouse of the order
    SELECT warehouse_id
    INTO wh_id
    FROM `Order`
    WHERE order_id = NEW.order_id;

    IF wh_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Order not found';
    END IF;

    -- Lock inventory row to prevent race conditions
    SELECT available_qty
    INTO avail
    FROM Inventory
    WHERE warehouse_id = wh_id
    AND product_id = NEW.product_id
    FOR UPDATE;

    -- Check stock
    IF avail IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Product not stocked in this warehouse';
    END IF;

    IF avail < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock available';
    END IF;

    -- Reserve stock
    UPDATE Inventory
    SET
        available_qty = available_qty - NEW.quantity,
        reserved_qty = reserved_qty + NEW.quantity
    WHERE warehouse_id = wh_id
    AND product_id = NEW.product_id;

END$$

DELIMITER ;
-- Trigger:Wallet Debit on Order Confirm
DELIMITER $$

CREATE TRIGGER trg_after_order_item_insert
AFTER INSERT ON Order_Item
FOR EACH ROW
BEGIN

    UPDATE `Order`
    SET 
        total_items = total_items + NEW.quantity,
        total_amount = total_amount + (NEW.quantity * NEW.unit_price_with_tax)
    WHERE order_id = NEW.order_id;

END$$

DELIMITER ;

DELIMITER $$

CREATE TRIGGER trg_after_order_item_update
AFTER UPDATE ON Order_Item
FOR EACH ROW
BEGIN

    UPDATE `Order`
    SET
        total_items =
            total_items - OLD.quantity + NEW.quantity,

        total_amount =
            total_amount
            - (OLD.quantity * OLD.unit_price_with_tax)
            + (NEW.quantity * NEW.unit_price_with_tax)

    WHERE order_id = NEW.order_id;

END$$

DELIMITER ;

DELIMITER $$

CREATE TRIGGER trg_after_order_item_delete
AFTER DELETE ON Order_Item
FOR EACH ROW
BEGIN

    UPDATE `Order`
    SET
        total_items = total_items - OLD.quantity,

        total_amount =
            total_amount - (OLD.quantity * OLD.unit_price_with_tax)

    WHERE order_id = OLD.order_id;

END$$

DELIMITER ;







DELIMITER $$

CREATE TRIGGER trg_after_order_confirm
AFTER UPDATE ON `Order`
FOR EACH ROW
BEGIN
    DECLARE total DECIMAL(10,2);
    DECLARE bal DECIMAL(10,2);

    IF OLD.order_status = 'CREATED'
       AND NEW.order_status = 'CONFIRMED' THEN

        SELECT order_total_with_tax
        INTO total
        FROM v_order_total
        WHERE order_id = NEW.order_id;

        SELECT balance
        INTO bal
        FROM Wallet
        WHERE customer_id = NEW.customer_id;

        IF bal < total THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient wallet balance';
        END IF;

        UPDATE Wallet
        SET balance = balance - total
        WHERE customer_id = NEW.customer_id;

        UPDATE Inventory i
        JOIN Order_Item oi ON oi.product_id = i.product_id
        SET
            i.reserved_qty = i.reserved_qty - oi.quantity
        WHERE
            oi.order_id = NEW.order_id
            AND i.warehouse_id = NEW.warehouse_id;

    END IF;
END$$

DELIMITER ;



-- ============================================================
-- STEP 1: Recreate the trigger that was missing
-- ============================================================

DELIMITER $$

CREATE TRIGGER trg_before_batch_insert
BEFORE INSERT ON Batch
FOR EACH ROW
BEGIN
    DECLARE current_used INT;
    DECLARE total_cap INT;
    DECLARE purchase_cost DECIMAL(12,2);
    DECLARE warehouse_budget DECIMAL(12,2);
    DECLARE prod_status VARCHAR(20);

    -- Check producer is approved
    SELECT approval_status
    INTO prod_status
    FROM Producer
    WHERE producer_id = NEW.producer_id;

    IF prod_status <> 'Approved' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Producer not approved';
    END IF;

    -- Get warehouse capacity
    SELECT used_capacity, total_capacity
    INTO current_used, total_cap
    FROM Warehouse
    WHERE warehouse_id = NEW.warehouse_id;

    -- Check capacity
    IF current_used + NEW.quantity > total_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse capacity exceeded';
    END IF;

    -- Calculate purchase cost
    SET purchase_cost = NEW.quantity * NEW.unit_cost;

    -- Get warehouse budget
    SELECT budget
    INTO warehouse_budget
    FROM Warehouse
    WHERE warehouse_id = NEW.warehouse_id;

    -- Check budget
    IF warehouse_budget < purchase_cost THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse budget exceeded';
    END IF;

    -- Update inventory
    INSERT INTO Inventory (warehouse_id, product_id, available_qty, reserved_qty)
    VALUES (NEW.warehouse_id, NEW.product_id, NEW.quantity, 0)
    ON DUPLICATE KEY UPDATE
        available_qty = available_qty + NEW.quantity;

    -- Deduct capacity and budget
    UPDATE Warehouse
    SET
        used_capacity = used_capacity + NEW.quantity,
        budget        = budget - purchase_cost
    WHERE warehouse_id = NEW.warehouse_id;

END$$

DELIMITER ;

-- ============================================================
-- STEP 2: Add quoted_price column to Restock_Request
--         (needed for price-change notification feature)
-- ============================================================

ALTER TABLE Restock_Request
ADD COLUMN IF NOT EXISTS quoted_price DECIMAL(10,2) NULL
COMMENT 'Price per unit at time warehouse sent the request';

-- ============================================================
-- STEP 3: Manually fix the budget for batches that already
--         came in BEFORE the trigger existed.
--         This calculates what SHOULD have been deducted.
-- ============================================================

UPDATE Warehouse w
SET w.budget = w.budget - (
    SELECT COALESCE(SUM(b.quantity * b.unit_cost), 0)
    FROM Batch b
    WHERE b.warehouse_id = w.warehouse_id
)
WHERE w.warehouse_id = 1;

-- ============================================================
-- STEP 4: Verify everything looks right
-- ============================================================

SELECT warehouse_id, warehouse_name, budget, used_capacity, total_capacity
FROM Warehouse;

SHOW TRIGGERS WHERE `Table` = 'Batch';




DELIMITER $$

CREATE TRIGGER trg_after_inventory_update
AFTER UPDATE ON Inventory
FOR EACH ROW
BEGIN
    DECLARE threshold INT;

    SELECT min_threshold INTO threshold
    FROM Reorder_Config
    WHERE product_id = NEW.product_id
    AND warehouse_id = NEW.warehouse_id;

    IF threshold IS NOT NULL AND NEW.available_qty < threshold THEN
        SIGNAL SQLSTATE '01000'
        SET MESSAGE_TEXT = 'Reorder required for this product';
    END IF;
END$$

DELIMITER ;


-- For the UI dashboards
-- View:Customer Products
CREATE VIEW v_customer_products AS
SELECT
    w.warehouse_name,
    p.product_name,
    ROUND(MIN(pp.price_before_tax) * 1.20, 2) AS price_after_tax,
    i.available_qty
FROM Inventory i
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
JOIN Product p ON i.product_id = p.product_id
JOIN Producer_Product pp ON p.product_id = pp.product_id
GROUP BY w.warehouse_name, p.product_name, i.available_qty;




-- View:Staff Inventory
CREATE VIEW v_staff_inventory AS
SELECT
    w.warehouse_name,
    p.product_name,
    i.available_qty,
    i.reserved_qty
FROM Inventory i
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
JOIN Product p ON i.product_id = p.product_id;

-- View: Low Stock Products
CREATE VIEW v_low_stock_products AS
SELECT
    w.warehouse_name,
    p.product_name,
    i.available_qty,
    r.min_threshold
FROM Inventory i
JOIN Reorder_Config r
    ON i.product_id = r.product_id
   AND i.warehouse_id = r.warehouse_id
JOIN Warehouse w
    ON i.warehouse_id = w.warehouse_id
JOIN Product p
    ON i.product_id = p.product_id
WHERE i.available_qty < r.min_threshold;

-- View:Warehouse Summary
CREATE VIEW v_warehouse_summary AS
SELECT
    warehouse_name,
    total_capacity,
    used_capacity,
    (total_capacity - used_capacity) AS free_capacity,
    ROUND((used_capacity / total_capacity) * 100, 2) AS utilization_percent
FROM Warehouse;

CREATE VIEW v_warehouse_revenue AS
SELECT
    w.warehouse_id,
    w.warehouse_name,
    SUM(oi.quantity * oi.unit_price_with_tax) AS total_revenue
FROM `Order` o
JOIN Order_Item oi ON o.order_id = oi.order_id
JOIN Warehouse w ON o.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name;

CREATE VIEW v_warehouse_cost AS
SELECT
    w.warehouse_id,
    w.warehouse_name,
    SUM(b.quantity * b.unit_cost) AS total_cost
FROM Batch b
JOIN Warehouse w ON b.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name;

CREATE VIEW v_warehouse_profit AS
SELECT
    o.warehouse_id,
    w.warehouse_name,
    SUM(oi.quantity * oi.unit_price_with_tax) AS revenue,
    SUM(oi.quantity * bc.avg_cost) AS cost,
    SUM(oi.quantity * oi.unit_price_with_tax)
      - SUM(oi.quantity * bc.avg_cost) AS profit
FROM `Order` o
JOIN Order_Item oi ON o.order_id = oi.order_id
JOIN Warehouse w ON o.warehouse_id = w.warehouse_id
JOIN (
    SELECT product_id, AVG(unit_cost) AS avg_cost
    FROM Batch
    GROUP BY product_id
) bc ON bc.product_id = oi.product_id
GROUP BY o.warehouse_id, w.warehouse_name;

CREATE VIEW v_warehouse_financial_dashboard AS
SELECT
    w.warehouse_name,
    w.budget AS remaining_budget,
    r.total_revenue,
    c.total_cost,
    (r.total_revenue - c.total_cost) AS profit
FROM Warehouse w
LEFT JOIN v_warehouse_revenue r
ON w.warehouse_id = r.warehouse_id
LEFT JOIN v_warehouse_cost c
ON w.warehouse_id = c.warehouse_id;

CREATE INDEX idx_orderitem_order
ON Order_Item(order_id);

CREATE INDEX idx_orderitem_product
ON Order_Item(product_id);


USE auth_db;
ALTER TABLE users ADD COLUMN linked_id INT DEFAULT NULL;
UPDATE users SET linked_id = 1 WHERE username = 'producer1';
UPDATE users SET linked_id = 1 WHERE username = 'testuser222';
UPDATE users SET linked_id = 1 WHERE username = 'admin1';
UPDATE users SET linked_id = 1 WHERE username = 'vansh';
UPDATE users SET linked_id = 1 WHERE username = 'asas';