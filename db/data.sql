--not complete , may be changed later

USE supplychain_db;

INSERT IGNORE INTO Producer (producer_id, producer_name, phone, email) VALUES
(1, 'Amul Dairy Ltd', '1111111111', 'contact@amul.com'),
(2, 'Britannia Industries', '2222222222', 'info@britannia.co.in'),
(3, 'Haldirams Pvt Ltd', '3333333333', 'support@haldirams.com'),
(4, 'Parle Products', '4444444444', 'contact@parle.com'),
(5, 'ITC Foods Ltd', '5555555555', 'foods@itc.in');

INSERT IGNORE INTO Product (product_id, product_name) VALUES
(1, 'Amul Milk'),
(2, 'Amul Butter'),
(3, 'Amul Chocolate'),

(4, 'Britannia Good Day Biscuits'),
(5, 'Britannia Cake Roll'),
(6, 'Britannia Marie Gold'),

(7, 'Haldirams Bhujia'),
(8, 'Haldirams Soan Papdi'),
(9, 'Haldirams Kaju Katli'),

(10, 'Parle G Biscuits'),
(11, 'Parle Hide & Seek'),
(12, 'Parle Melody Toffee'),

(13, 'Sunfeast Dark Fantasy'),
(14, 'Aashirvaad Atta'),
(15, 'Bingo Mad Angles');
-- Insert Producer ↔ Product Mapping

INSERT IGNORE INTO Producer_Product
(producer_id, product_id, price_before_tax, max_batch_limit) VALUES

-- Amul
(1, 1, 30.00, 500),
(1, 2, 55.00, 400),
(1, 3, 120.00, 300),

-- Britannia
(2, 4, 25.00, 600),
(2, 5, 35.00, 500),
(2, 6, 20.00, 700),

-- Haldirams
(3, 7, 40.00, 450),
(3, 8, 120.00, 200),
(3, 9, 600.00, 150),

-- Parle
(4, 10, 10.00, 1000),
(4, 11, 30.00, 500),
(4, 12, 5.00, 1500),

-- ITC
(5, 13, 150.00, 300),
(5, 14, 350.00, 250),
(5, 15, 20.00, 800);

-- Insert Customers
INSERT INTO Customer (first_name, last_name, email) VALUES
('Amit', 'Verma', 'amit@gmail.com'),
('Sneha', 'Kapoor', 'sneha@gmail.com'),
('Rohit', 'Gupta', 'rohit@gmail.com'),
('Priya', 'Shah', 'priya@gmail.com'),
('Arjun', 'Patel', 'arjun@gmail.com'),
('Neha', 'Singh', 'neha@gmail.com'),
('Vikas', 'Mehta', 'vikas@gmail.com'),
('Karan', 'Malhotra', 'karan@gmail.com');

-- Insert Warehouses
INSERT IGNORE INTO Warehouse 
(warehouse_id, warehouse_name, total_capacity, used_capacity, budget)
VALUES
(1, 'Main Warehouse', 10000, 0, 200000);


INSERT INTO Admin (admin_name, warehouse_id)
VALUES ('Main Admin', 1);


UPDATE Producer
SET approval_status = 'Approved';
-- Insert Batches (Triggers populate Inventory)
INSERT INTO Batch (producer_id, product_id, warehouse_id, quantity, unit_cost, arrival_date) VALUES
(1,1,1,200,12.00,CURDATE()),
(1,2,1,150,40.00,CURDATE()),
(1,3,1,100,80.00,CURDATE()),

(2,4,1,300,15.00,CURDATE()),
(2,5,1,200,20.00,CURDATE()),
(2,6,1,250,12.00,CURDATE()),

(3,7,1,180,25.00,CURDATE()),
(3,8,1,120,70.00,CURDATE()),
(3,9,1,60,400.00,CURDATE()),

(4,10,1,400,5.00,CURDATE()),
(4,11,1,200,15.00,CURDATE()),
(4,12,1,500,2.00,CURDATE()),

(5,13,1,120,90.00,CURDATE()),
(5,14,1,150,250.00,CURDATE()),
(5,15,1,300,10.00,CURDATE());

-- Insert Wallets
INSERT INTO Wallet (customer_id, balance) VALUES
(1, 1500),
(2, 2000),
(3, 800),
(4, 2500),
(5, 1200),
(6, 1800),
(7, 1000),
(8, 2200);

-- Insert Reorder Configuration
INSERT INTO Reorder_Config (product_id, warehouse_id, min_threshold) VALUES
(1, 1, 120),
(2, 1, 80),
(3, 1, 60),
(4, 1, 40),
(5, 1, 35);


-- Create a Sample Order


INSERT INTO `Order` (customer_id, warehouse_id) VALUES
(1,1),
(2,1),
(3,1),
(4,1),
(5,1),
(6,1),
(7,1),
(8,1);


-- Add Items to the Order

INSERT INTO Order_Item (order_id, product_id, quantity, unit_price) VALUES
(1,1,5,12),
(1,4,3,15),

(2,2,2,40),
(2,7,1,25),

(3,10,10,5),
(3,11,4,15),

(4,13,1,90),
(4,5,2,20),

(5,15,6,10),
(5,6,5,12),

(6,1,2,12),
(6,5,1,20),

(7,10,6,5),
(7,2,2,40),

(8,7,3,25),
(8,13,1,90);


-- Check Order Totals (Triggers should update automatically)

UPDATE `Order`
SET order_status='CONFIRMED'
WHERE order_id IN (1,2,3);




SELECT
    order_id,
    total_items,
    total_amount
FROM `Order`
WHERE order_id = 1;



-- Confirm the Order
-- (Wallet trigger will execute)


UPDATE `Order`
SET order_status = 'CONFIRMED'
WHERE order_id = 1;


