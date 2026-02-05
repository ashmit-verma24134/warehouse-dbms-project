CREATE DATABASE IF NOT EXISTS supplychain_db;
USE supplychain_db;

--Drop table and views solely for debugging purpose so that we can rerun schema without overwriting previous schemas 
DROP VIEW IF EXISTS v_warehouse_summary;
DROP VIEW IF EXISTS v_low_stock_products;
DROP TABLE IF EXISTS Reorder_Config;
DROP VIEW IF EXISTS v_staff_inventory;
DROP VIEW IF EXISTS v_customer_products;
DROP VIEW IF EXISTS v_order_total;
DROP TABLE IF EXISTS Order_Item;
DROP TABLE IF EXISTS `Order`;
DROP TABLE IF EXISTS Inventory;
DROP TABLE IF EXISTS Batch;
DROP TABLE IF EXISTS Wallet;
DROP TABLE IF EXISTS Customer;
DROP TABLE IF EXISTS Warehouse;
DROP TABLE IF EXISTS Producer_Product;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Producer;

-- Producer Table
CREATE TABLE Producer (
    producer_id INT AUTO_INCREMENT PRIMARY KEY, --db generate ids automatically
    producer_name VARCHAR(100) NOT NULL,
    --Composite attribute Contact info
    phone VARCHAR(15) NOT NULL,
    email VARCHAR(100) NOT NULL,
    
    --Business logic if producer registers his  product admin will allow if his product shipment to warehouse is approved/pending/rejected
    approval_status ENUM('Pending','Approved','Rejected')
        NOT NULL DEFAULT 'Pending' --automatic status pending
)ENGINE=InnoDB;


--Product Table
CREATE TABLE Product (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL UNIQUE,
    category VARCHAR(50)  --Group to which product belongs too
)ENGINE=InnoDB;

--Producer_prodcut table many to many (supplies relationship):-
CREATE TABLE Producer_Product (
    producer_id INT NOT NULL,
    product_id  INT NOT NULL,

    -- Relationship attributes (SUPPLIES)
    price_before_tax DECIMAL(10,2) NOT NULL,
    max_batch_limit  INT NOT NULL, --Maxm quantity allowed per suplly batch

    PRIMARY KEY (producer_id, product_id), --M:N

    CONSTRAINT fk_pp_producer
        FOREIGN KEY (producer_id)
        REFERENCES Producer(producer_id)
        ON DELETE RESTRICT  --Cant delete parent row if it exists inn child row
        ON UPDATE CASCADE,  --On update 

    CONSTRAINT fk_pp_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT chk_price_positive
        CHECK (price_before_tax > 0),

    CONSTRAINT chk_max_batch_limit
        CHECK (max_batch_limit > 0)
)ENGINE=InnoDB;

--Indexes for direct search(fast search)
--Using a B-Tree for indexing
CREATE INDEX idx_pp_producer ON Producer_Product(producer_id);
CREATE INDEX idx_pp_product ON Producer_Product(product_id);

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



--Warehouse Table
CREATE TABLE Warehouse (
    warehouse_id INT AUTO_INCREMENT PRIMARY KEY,  --RN Inntentionally multiple 
    warehouse_name VARCHAR(100) NOT NULL,
    total_capacity INT NOT NULL,
    used_capacity INT NOT NULL,

    CONSTRAINT chk_total_capacity
        CHECK (total_capacity > 0),

    CONSTRAINT chk_used_capacity_nonneg
        CHECK (used_capacity >= 0),

    CONSTRAINT chk_used_le_total
        CHECK (used_capacity <= total_capacity)
) ENGINE=InnoDB;

--Admin Table (1:1 with Warehouse)
CREATE TABLE Admin (
    admin_id INT AUTO_INCREMENT PRIMARY KEY,
    admin_name VARCHAR(100) NOT NULL,
    warehouse_id INT NOT NULL UNIQUE, --No two admins can reference the same warehouse 
    CONSTRAINT fk_admin_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES Warehouse(warehouse_id)
        ON DELETE CASCADE
)ENGINE=InnoDB;


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

-- Order Table 
CREATE TABLE `Order`(
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    order_status ENUM('CREATED', 'CONFIRMED', 'FAILED','DISPATCHED','DELIVERED') NOT NULL DEFAULT 'CREATED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES Customer(customer_id),

    CONSTRAINT fk_order_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES Warehouse(warehouse_id)
)ENGINE=InnoDB;

-- Order Item Table
CREATE TABLE Order_Item (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id   INT NOT NULL,
    product_id INT NOT NULL,
    quantity   INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    -- Derived attribute (20% tax)
    unit_price_with_tax DECIMAL(10,2)
        GENERATED ALWAYS AS (unit_price * 1.20) STORED,

    -- Prevent duplicate products in the same order
    CONSTRAINT uq_order_product
        UNIQUE (order_id, product_id),

    -- Domain constraint
    CONSTRAINT chk_order_item_qty
        CHECK (quantity > 0),

    -- Referential integrity
    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id)
        REFERENCES `Order`(order_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_order_item_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id)
)ENGINE=InnoDB;



-- View: Order Total
CREATE VIEW v_order_total AS
SELECT
    order_id,
    SUM(quantity * unit_price) AS order_total
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


--Trigger: Update Inventory & Enforce Capacity
--Whenever a new batch arrives, this trigger checks warehouse capacity and updates inventory automatically.
DELIMITER $$

CREATE TRIGGER trg_after_batch_insert
AFTER INSERT ON Batch
FOR EACH ROW
BEGIN
    DECLARE current_used INT;
    DECLARE total_cap INT;

    SELECT used_capacity, total_capacity
    INTO current_used, total_cap
    FROM Warehouse
    WHERE warehouse_id = NEW.warehouse_id;

    IF current_used + NEW.quantity > total_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse capacity exceeded';
    END IF;

    INSERT INTO Inventory (warehouse_id, product_id, available_qty, reserved_qty)
    VALUES (NEW.warehouse_id, NEW.product_id, NEW.quantity, 0)
    ON DUPLICATE KEY UPDATE
        available_qty = available_qty + NEW.quantity;

    UPDATE Warehouse
    SET used_capacity = used_capacity + NEW.quantity
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

    SELECT available_qty
    INTO avail
    FROM Inventory
    WHERE warehouse_id = (
        SELECT warehouse_id FROM `Order` WHERE order_id = NEW.order_id
    )
    AND product_id = NEW.product_id;

    IF avail IS NULL OR avail < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock available';
    END IF;

    UPDATE Inventory
    SET
        available_qty = available_qty - NEW.quantity,
        reserved_qty = reserved_qty + NEW.quantity
    WHERE warehouse_id = (
        SELECT warehouse_id FROM `Order` WHERE order_id = NEW.order_id
    )
    AND product_id = NEW.product_id;
END$$

DELIMITER ;

--Trigger:Wallet Debit on Order Confirm
DELIMITER $$

CREATE TRIGGER trg_after_order_confirm
AFTER UPDATE ON `Order`
FOR EACH ROW
BEGIN
    DECLARE total DECIMAL(10,2);
    DECLARE bal DECIMAL(10,2);

    IF OLD.order_status = 'CREATED'
       AND NEW.order_status = 'CONFIRMED' THEN

        SELECT order_total
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



--For the UI dashboards
-- View:Customer Products
CREATE VIEW v_customer_products AS
SELECT
    w.warehouse_name,
    p.product_name,
    ROUND(pp.price_before_tax * 1.20, 2) AS price_after_tax,
    i.available_qty
FROM Inventory i
JOIN Warehouse w ON i.warehouse_id = w.warehouse_id
JOIN Product p ON i.product_id = p.product_id
JOIN Producer_Product pp ON p.product_id = pp.product_id;




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