-- =========================================
-- Supply Chain Database Data
-- =========================================

USE supplychain_db;

-- =========================================
-- Insert Producers
-- =========================================
INSERT IGNORE INTO Producer (producer_id, producer_name, contact_info) VALUES
(1, 'Pet Food Pvt Ltd', '1111111111'),
(2, 'Home Decor Pvt Ltd', '2222222222'),
(3, 'Urban Living Pvt Ltd', '3333333333'),
(4, 'Eco Essentials Pvt Ltd', '4444444444'),
(5, 'Canned Food Pvt Ltd', '5555555555');

-- =========================================
-- Insert Products
-- =========================================
INSERT IGNORE INTO Product (product_id, product_name) VALUES
(1, 'Cat Food'),
(2, 'Dog Food'),
(3, 'Wall Art'),
(4, 'Mirror'),
(5, 'Indoor Plant'),
(6, 'Lamp'),
(7, 'Decorative Vase'),
(8, 'Vacuum Cleaner'),
(9, 'Car Cleaning Kit'),
(10, 'Smart LED Bulb'),
(11, 'Reusable Cloth Bag'),
(12, 'Solar Powered Lantern'),
(13, 'Canned Beans'),
(14, 'Canned Sweet Corn'),
(15, 'Canned Tuna Fish');

-- =========================================
-- Insert Producer ↔ Product Mapping
-- =========================================
INSERT IGNORE INTO Producer_Product (producer_id, product_id, price_before_tax) VALUES
(1, 1, 10.00),
(1, 2, 10.00),

(2, 3, 50.00),
(2, 4, 50.00),
(2, 5, 50.00),
(2, 6, 50.00),
(2, 7, 50.00),

(3, 8, 60.00),
(3, 9, 60.00),
(3, 10, 60.00),

(4, 11, 20.00),
(4, 12, 20.00),

(5, 13, 30.00),
(5, 14, 30.00),
(5, 15, 30.00);


-- =========================================
-- Insert Customers
-- =========================================
INSERT IGNORE INTO Customer (customer_id, customer_name, email) VALUES
(1, 'Test Customer', 'test@example.com'),
(2, 'Rahul Sharma', 'rahul@gmail.com');

-- =========================================
-- Insert Warehouses
-- =========================================
INSERT IGNORE INTO Warehouse (warehouse_id, warehouse_name, total_capacity, used_capacity) VALUES
(1, 'Main Warehouse', 1000, 200);

-- =========================================
-- Insert Inventory
-- =========================================
INSERT IGNORE INTO Inventory (warehouse_id, product_id, available_qty, reserved_qty) VALUES
(1, 1, 100, 0),
(1, 2, 100, 0),
(1, 3, 50, 0),
(1, 4, 50, 0),
(1, 5, 30, 0);

-- =========================================
-- Insert Wallets
-- =========================================
INSERT IGNORE INTO Wallet (customer_id, balance) VALUES
(1, 1000.00),
(2, 500.00);
