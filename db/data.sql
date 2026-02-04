-- =========================================
-- Supply Chain Database Data
-- =========================================

USE supplychain_db;

-- =========================================
-- Insert Producers
-- =========================================
INSERT IGNORE INTO Producer (producer_id, producer_name, phone, email) VALUES
(1, 'Pet Food Pvt Ltd', '1111111111', 'pet@food.com'),
(2, 'Home Decor Pvt Ltd', '2222222222','home@decor.com'),
(3, 'Urban Living Pvt Ltd', '3333333333','urban@living.com'),
(4, 'Eco Essentials Pvt Ltd', '4444444444','eco@essential.com'),
(5, 'Canned Food Pvt Ltd', '5555555555','canned@food.com');


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
INSERT IGNORE INTO Producer_Product
(producer_id, product_id, price_before_tax, max_batch_limit) VALUES
(1, 1, 10.00, 500),
(1, 2, 10.00, 500),

(2, 3, 50.00, 200),
(2, 4, 50.00, 200),
(2, 5, 50.00, 200),
(2, 6, 50.00, 200),
(2, 7, 50.00, 200),

(3, 8, 60.00, 150),
(3, 9, 60.00, 150),
(3, 10, 60.00, 150),

(4, 11, 20.00, 300),
(4, 12, 20.00, 300),

(5, 13, 30.00, 400),
(5, 14, 30.00, 400),
(5, 15, 30.00, 400);

-- =========================================
-- Insert Customers
-- =========================================
INSERT IGNORE INTO Customer (customer_id, first_name, last_name, email) VALUES
(1, 'Test', 'Customer', 'test@example.com'),
(2, 'Rahul', 'Sharma', 'rahul@gmail.com');

-- =========================================
-- Insert Warehouses
-- =========================================
INSERT IGNORE INTO Warehouse (warehouse_id, warehouse_name, total_capacity, used_capacity) VALUES
(1, 'Main Warehouse', 1000, 0);


INSERT INTO Admin (admin_name, warehouse_id)
VALUES ('Main Admin', 1);

-- =========================================
-- Insert Batches (Triggers populate Inventory)
-- =========================================
INSERT INTO Batch (producer_id, product_id, warehouse_id, quantity, unit_cost, arrival_date) VALUES
(1, 1, 1, 100, 10.00, CURDATE()),
(1, 2, 1, 100, 10.00, CURDATE()),
(2, 3, 1, 50, 50.00, CURDATE()),
(2, 4, 1, 50, 50.00, CURDATE()),
(2, 5, 1, 30, 50.00, CURDATE());

-- =========================================
-- Insert Wallets
-- =========================================
INSERT IGNORE INTO Wallet (customer_id, balance) VALUES
(1, 1000.00),
(2, 500.00);

-- =========================================
-- Insert Reorder Configuration
-- =========================================
INSERT INTO Reorder_Config (product_id, warehouse_id, min_threshold) VALUES
(1, 1, 120),
(2, 1, 80),
(3, 1, 60),
(4, 1, 40),
(5, 1, 35);

-- =========================================
-- Sample Order (for backend + triggers)
-- =========================================
INSERT INTO `Order` (order_id, customer_id, warehouse_id)
VALUES (1, 1, 1);

INSERT INTO Order_Item (order_id, product_id, quantity, unit_price)
VALUES
(1, 1, 3, 10.00);

UPDATE `Order`
SET order_status = 'CONFIRMED'
WHERE order_id = 1;
