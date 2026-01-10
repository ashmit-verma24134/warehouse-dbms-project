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
    producer_id INT AUTO_INCREMENT PRIMARY KEY,
    producer_name VARCHAR(100) NOT NULL,
    contact_info VARCHAR(100)
);

-- =========================================
-- Product Table
-- =========================================
CREATE TABLE Product (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL
);

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
        REFERENCES Producer(producer_id),

    CONSTRAINT fk_pp_product
        FOREIGN KEY (product_id)
        REFERENCES Product(product_id),

    -- Business Rule Constraint
    CONSTRAINT chk_price_positive
        CHECK (price_before_tax > 0)
);
