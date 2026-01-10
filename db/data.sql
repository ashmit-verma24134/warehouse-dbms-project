-- =========================================
-- Supply Chain Database Data
-- =========================================

USE supplychain_db;

-- =========================================
-- Insert Producers
-- =========================================
INSERT INTO Producer (producer_name, contact_info) VALUES
('Pet Food Pvt Ltd', '1111111111'),
('Home Decor Pvt Ltd', '2222222222'),
('Urban Living Pvt Ltd', '3333333333'),
('Eco Essentials Pvt Ltd', '4444444444'),
('Canned Food Pvt Ltd', '5555555555');

-- =========================================
-- Insert Products
-- =========================================
INSERT INTO Product (product_name) VALUES
('Cat Food'),
('Dog Food'),
('Wall Art'),
('Mirror'),
('Indoor Plant'),
('Lamp'),
('Decorative Vase'),
('Vacuum Cleaner'),
('Car Cleaning Kit'),
('Smart LED Bulb'),
('Reusable Cloth Bag'),
('Solar Powered Lantern'),
('Canned Beans'),
('Canned Sweet Corn'),
('Canned Tuna Fish');

-- =========================================
-- Insert Producer ↔ Product Mapping
-- =========================================
INSERT INTO Producer_Product (producer_id, product_id, price_before_tax) VALUES
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
