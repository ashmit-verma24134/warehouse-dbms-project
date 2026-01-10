-- =========================================
-- Supply Chain Database Schema
-- =========================================

-- Create database
CREATE DATABASE IF NOT EXISTS supplychain_db;
USE supplychain_db;

-- =========================================
-- Drop tables (order matters because of FKs)
-- =========================================
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

    -- Composite Primary Key
    PRIMARY KEY (producer_id, product_id),

    -- Foreign Key Constraints
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

    -- Business Rule Constraint
    CONSTRAINT chk_price_positive
        CHECK (price_before_tax > 0)
) ENGINE=InnoDB;

-- =========================================
-- Indexes for Efficient Access
-- =========================================
CREATE INDEX idx_pp_producer ON Producer_Product(producer_id);
CREATE INDEX idx_pp_product ON Producer_Product(product_id);
