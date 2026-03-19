USE supplychain_db;

DROP PROCEDURE IF EXISTS sp_place_order;
DROP PROCEDURE IF EXISTS sp_fulfill_request;
DROP PROCEDURE IF EXISTS sp_cancel_order;
DROP PROCEDURE IF EXISTS sp_add_funds;
DROP PROCEDURE IF EXISTS sp_approve_producer;


-- STORED PROCEDURE 1: sp_place_order
-- Creates an order + inserts all items + confirms in one call
-- Called from Flask: CALL sp_place_order(customer_id, warehouse_id, items_json, OUT order_id, OUT error_msg)
--
-- Chapter 5 concept: Stored Procedure with IN/OUT params,
-- conditional logic, exception handling, multiple DML statements

DELIMITER $$

CREATE PROCEDURE sp_place_order(
    IN  p_customer_id  INT,
    IN  p_warehouse_id INT,
    OUT p_order_id     INT,
    OUT p_error        VARCHAR(255)
)
BEGIN
    DECLARE v_wallet_balance DECIMAL(10,2);
    DECLARE v_customer_exists INT DEFAULT 0;
    DECLARE v_warehouse_exists INT DEFAULT 0;

    -- Error handler: if anything goes wrong, rollback and set error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error = MESSAGE_TEXT;
        ROLLBACK;
        SET p_order_id = -1;
    END;

    SET p_error    = NULL;
    SET p_order_id = -1;

    START TRANSACTION;

    -- Validate customer exists
    SELECT COUNT(*) INTO v_customer_exists
    FROM Customer WHERE customer_id = p_customer_id;

    IF v_customer_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Customer not found';
    END IF;

    -- Validate warehouse exists
    SELECT COUNT(*) INTO v_warehouse_exists
    FROM Warehouse WHERE warehouse_id = p_warehouse_id;

    IF v_warehouse_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Warehouse not found';
    END IF;

    -- Validate wallet exists
    SELECT balance INTO v_wallet_balance
    FROM Wallet WHERE customer_id = p_customer_id;

    IF v_wallet_balance IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No wallet found for this customer';
    END IF;

    -- Create the order
    INSERT INTO `Order` (customer_id, warehouse_id, order_status)
    VALUES (p_customer_id, p_warehouse_id, 'CREATED');

    SET p_order_id = LAST_IN

-- STORED PROCEDURE 2: sp_fulfill_request
-- Producer fulfills a restock request: creates Batch,
-- updates earnings, marks request Fulfilled
-- All in one atomic transaction
--
-- Chapter 5 concept: Stored Procedure, FOR UPDATE locking,
-- SIGNAL for business rule violations, multi-table updates

DELIMITER $$

CREATE PROCEDURE sp_fulfill_request(
    IN  p_request_id  INT,
    IN  p_producer_id INT,
    OUT p_batch_id    INT,
    OUT p_error       VARCHAR(255)
)
BEGIN
    DECLARE v_warehouse_id   INT;
    DECLARE v_product_id     INT;
    DECLARE v_requested_qty  INT;
    DECLARE v_current_price  DECIMAL(10,2);
    DECLARE v_quoted_price   DECIMAL(10,2);
    DECLARE v_status         VARCHAR(20);
    DECLARE v_total_val      DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error = MESSAGE_TEXT;
        ROLLBACK;
        SET p_batch_id = -1;
    END;

    SET p_error    = NULL;
    SET p_batch_id = -1;

    START TRANSACTION;

    -- Lock and fetch the request
    SELECT rr.warehouse_id, rr.product_id, rr.requested_qty,
           rr.status, rr.quoted_price, pp.price_before_tax
    INTO   v_warehouse_id, v_product_id, v_requested_qty,
           v_status, v_quoted_price, v_current_price
    FROM   Restock_Request rr
    JOIN   Producer_Product pp
           ON pp.producer_id = rr.producer_id AND pp.product_id = rr.product_id
    WHERE  rr.request_id = p_request_id
      AND  rr.producer_id = p_producer_id
    FOR UPDATE;

    -- Validate request exists and belongs to this producer
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Request not found or does not belong to this producer';
    END IF;

    -- Check status
    IF v_status <> 'Pending' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Request is not in Pending status';
    END IF;

    -- Check price mismatch (warehouse must accept new price first)
    IF v_quoted_price IS NOT NULL AND ABS(v_quoted_price - v_current_price) > 0.001 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Price mismatch — warehouse must accept updated price first';
    END IF;

    -- Calculate total
    SET v_total_val = v_requested_qty * v_current_price;

    -- Insert Batch (trg_before_batch_insert handles inventory + budget)
    INSERT INTO Batch (producer_id, product_id, warehouse_id, request_id,
                       quantity, unit_cost, arrival_date)
    VALUES (p_producer_id, v_product_id, v_warehouse_id, p_request_id,
            v_requested_qty, v_current_price, CURDATE());

    SET p_batch_id = LAST_INSERT_ID();

    -- Update producer earnings
    UPDATE Producer
    SET earnings = earnings + v_total_val
    WHERE producer_id = p_producer_id;

    -- Mark request fulfilled
    UPDATE Restock_Request
    SET status = 'Fulfilled'
    WHERE request_id = p_request_id;

    COMMIT;
    SET p_error = NULL;
END$$

DELIMITER ;



-- STORED PROCEDURE 3: sp_cancel_order
-- Customer cancels a CREATED order:
-- restores inventory reserved_qty → available_qty,
-- refunds wallet if already CONFIRMED,
-- marks order FAILED
--
-- Chapter 5 concept: Stored Procedure, CASE statement,
-- conditional refund logic, multi-table transaction

DELIMITER $$

CREATE PROCEDURE sp_cancel_order(
    IN  p_order_id    INT,
    IN  p_customer_id INT,
    OUT p_refund      DECIMAL(12,2),
    OUT p_error       VARCHAR(255)
)
BEGIN
    DECLARE v_status       VARCHAR(20);
    DECLARE v_warehouse_id INT;
    DECLARE v_order_total  DECIMAL(12,2);
    DECLARE v_cust_check   INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error = MESSAGE_TEXT;
        ROLLBACK;
        SET p_refund = 0;
    END;

    SET p_error  = NULL;
    SET p_refund = 0;

    START TRANSACTION;

    -- Fetch order and lock it
    SELECT order_status, warehouse_id, total_amount
    INTO   v_status, v_warehouse_id, v_order_total
    FROM   `Order`
    WHERE  order_id = p_order_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Order not found';
    END IF;

    -- Validate ownership
    SELECT COUNT(*) INTO v_cust_check
    FROM `Order`
    WHERE order_id = p_order_id AND customer_id = p_customer_id;

    IF v_cust_check = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This order does not belong to you';
    END IF;

    -- Only CREATED or CONFIRMED orders can be cancelled
    IF v_status NOT IN ('CREATED', 'CONFIRMED') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Only CREATED or CONFIRMED orders can be cancelled';
    END IF;

    -- Restore reserved inventory back to available
    UPDATE Inventory i
    JOIN Order_Item oi ON oi.product_id = i.product_id
    SET i.available_qty = i.available_qty + oi.quantity,
        i.reserved_qty  = i.reserved_qty  - oi.quantity
    WHERE oi.order_id    = p_order_id
      AND i.warehouse_id = v_warehouse_id;

    -- If CONFIRMED, refund wallet
    IF v_status = 'CONFIRMED' THEN
        UPDATE Wallet
        SET balance = balance + v_order_total
        WHERE customer_id = p_customer_id;

        SET p_refund = v_order_total;
    END IF;

    -- Mark order as FAILED (cancelled)
    UPDATE `Order`
    SET order_status = 'FAILED'
    WHERE order_id = p_order_id;

    -- Log cancellation
    INSERT INTO Order_Cancellation (order_id, customer_id, refund_amount)
    VALUES (p_order_id, p_customer_id, p_refund);

    COMMIT;
    SET p_error = NULL;
END$$

DELIMITER ;



-- STORED PROCEDURE 4: sp_add_funds
-- Adds money to a customer's wallet
-- Creates wallet if it doesn't exist (upsert pattern)
--
-- Chapter 5 concept: Stored Procedure with IF/ELSE,
-- INSERT ... ON DUPLICATE KEY, OUT parameter

DELIMITER $$

CREATE PROCEDURE sp_add_funds(
    IN  p_customer_id  INT,
    IN  p_amount       DECIMAL(10,2),
    OUT p_new_balance  DECIMAL(10,2),
    OUT p_error        VARCHAR(255)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error = MESSAGE_TEXT;
        ROLLBACK;
        SET p_new_balance = -1;
    END;

    SET p_error       = NULL;
    SET p_new_balance = -1;

    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Amount must be greater than zero';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists
    FROM Wallet WHERE customer_id = p_customer_id;

    IF v_exists > 0 THEN
        UPDATE Wallet
        SET balance = balance + p_amount
        WHERE customer_id = p_customer_id;
    ELSE
        INSERT INTO Wallet (customer_id, balance)
        VALUES (p_customer_id, p_amount);
    END IF;

    SELECT balance INTO p_new_balance
    FROM Wallet WHERE customer_id = p_customer_id;

    COMMIT;
    SET p_error = NULL;
END$$

DELIMITER ;



-- STORED PROCEDURE 5: sp_approve_producer
-- Admin approves or rejects a producer
-- Validates the status value, updates, returns result
--
-- Chapter 5 concept: Stored Procedure with CASE statement,
-- admin workflow automation, validation logic

DELIMITER $$

CREATE PROCEDURE sp_approve_producer(
    IN  p_producer_id INT,
    IN  p_new_status  VARCHAR(20),  -- 'Approved' or 'Rejected'
    IN  p_admin_id    INT,
    OUT p_error       VARCHAR(255)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_old_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error = MESSAGE_TEXT;
        ROLLBACK;
    END;

    SET p_error = NULL;

    -- Validate status value
    IF p_new_status NOT IN ('Approved', 'Rejected', 'Pending') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid status. Must be Approved, Rejected, or Pending';
    END IF;

    START TRANSACTION;

    SELECT approval_status
    INTO v_old_status
    FROM Producer
    WHERE producer_id = p_producer_id;

    IF v_old_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Producer not found';
    END IF;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Producer not found';
    END IF;

    UPDATE Producer
    SET approval_status = p_new_status
    WHERE producer_id = p_producer_id;

    COMMIT;
    SET p_error = NULL;
END$$

DELIMITER ;



-- SUPPORTING TABLE: Order_Cancellation
-- Logs every cancelled order for audit purposes
-- Used by sp_cancel_order

CREATE TABLE IF NOT EXISTS Order_Cancellation (
    cancellation_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id        INT NOT NULL,
    customer_id     INT NOT NULL,
    refund_amount   DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    cancelled_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id)    REFERENCES `Order`(order_id),
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id)
) ENGINE=InnoDB;



-- VERIFY: show all procedures created

SHOW PROCEDURE STATUS WHERE Db = 'supplychain_db';