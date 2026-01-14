
-- =========================================
-- Supply Chain Database Schema
-- =========================================

-- Create database
CREATE DATABASE IF NOT EXISTS supplychain_db;
USE supplychain_db;

-- =========================================
-- Drop tables (order matters because of FKs)
-- =========================================

DROP TABLE IF EXISTS Inventory;
DROP TABLE IF EXISTS Batch;

DROP TABLE IF EXISTS Wallet;
DROP TABLE IF EXISTS Customer;
DROP TABLE IF EXISTS Warehouse;

DROP TABLE IF EXISTS Producer_Product;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Producer;



-- =========================================
-- Producer Table
-- =========================================
CREATE TABLE Producer (
    producer_id INT AUTO_INCREMENT,
    producer_name VARCHAR(100) NOT NULL,
    contact_info VARCHAR(100),

    PRIMARY KEY (producer_id)
) ENGINE=InnoDB;

-- =========================================
-- Product Table
-- =========================================
CREATE TABLE Product (
    product_id INT AUTO_INCREMENT,
    product_name VARCHAR(100) NOT NULL,

    PRIMARY KEY (product_id)
) ENGINE=InnoDB;

-- =========================================
-- Producer ↔ Product (Many-to-Many)
-- =========================================
CREATE TABLE Producer_Product (
    producer_id INT NOT NULL,
    product_id INT NOT NULL,
    price_before_tax DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (producer_id, product_id),

    CONSTRAINT fk_pp_producer
        FOREIGN KEY (producer_id)
        REFERENCES Producer(producer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_pp_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT chk_price_positive
        CHECK (price_before_tax > 0)
) ENGINE=InnoDB;

-- =========================================
-- Indexes for Efficient Access
-- =========================================
CREATE INDEX idx_pp_producer ON Producer_Product(producer_id);
CREATE INDEX idx_pp_product ON Producer_Product(product_id);

-- =========================================
-- Warehouse Table
-- =========================================
CREATE TABLE Warehouse (
    warehouse_id INT AUTO_INCREMENT PRIMARY KEY,
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

-- =========================================
-- Customer Table
-- =========================================
CREATE TABLE Customer (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- =========================================
-- Wallet Table (1-to-1 with Customer)
-- =========================================
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
) ENGINE=InnoDB;

-- =========================================
-- Batch Table (Procurement)
-- =========================================
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
) ENGINE=InnoDB;


-- =========================================
-- Inventory Table (Current Stock)
-- =========================================
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


-- =========================================
-- Trigger: Update Inventory & Enforce Capacity
-- =========================================
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

