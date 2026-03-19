USE supplychain_db;

-- ============================================================
-- AUDIT LOG TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS Audit_Log (
    log_id        INT AUTO_INCREMENT PRIMARY KEY,
    table_name    VARCHAR(50)                      NOT NULL,
    operation     ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id     INT                              NOT NULL,
    changed_field VARCHAR(100)                     NULL,
    old_value     TEXT                             NULL,
    new_value     TEXT                             NULL,
    changed_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    note          VARCHAR(255) NULL
) ENGINE=InnoDB;

DELIMITER $$

-- ============================================================
-- AUDIT TRIGGER 1: Producer approval status change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_producer_status$$
CREATE TRIGGER trg_audit_producer_status
AFTER UPDATE ON Producer
FOR EACH ROW
BEGIN
    IF OLD.approval_status <> NEW.approval_status THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Producer',
            'UPDATE',
            NEW.producer_id,
            'approval_status',
            OLD.approval_status,
            NEW.approval_status,
            CONCAT('Producer: ', NEW.producer_name)
        );
    END IF;
END$$


-- ============================================================
-- AUDIT TRIGGER 2: Producer earnings change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_producer_earnings$$
CREATE TRIGGER trg_audit_producer_earnings
AFTER UPDATE ON Producer
FOR EACH ROW
BEGIN
    IF OLD.earnings <> NEW.earnings THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Producer',
            'UPDATE',
            NEW.producer_id,
            'earnings',
            CAST(OLD.earnings AS CHAR),
            CAST(NEW.earnings AS CHAR),
            CONCAT('Earnings updated for: ', NEW.producer_name)
        );
    END IF;
END$$


-- ============================================================
-- AUDIT TRIGGER 3: Price change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_price_change$$
CREATE TRIGGER trg_audit_price_change
AFTER UPDATE ON Producer_Product
FOR EACH ROW
BEGIN
    IF OLD.price_before_tax <> NEW.price_before_tax THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Producer_Product',
            'UPDATE',
            NEW.producer_id,
            'price_before_tax',
            CAST(OLD.price_before_tax AS CHAR),
            CAST(NEW.price_before_tax AS CHAR),
            CONCAT('Product ID: ', NEW.product_id)
        );
    END IF;
END$$


-- ============================================================
-- AUDIT TRIGGER 4: Order status change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_order_status$$
CREATE TRIGGER trg_audit_order_status
AFTER UPDATE ON `Order`
FOR EACH ROW
BEGIN
    IF OLD.order_status <> NEW.order_status THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Order',
            'UPDATE',
            NEW.order_id,
            'order_status',
            OLD.order_status,
            NEW.order_status,
            CONCAT('Customer ID: ', NEW.customer_id, ' | Amount: ', NEW.total_amount)
        );
    END IF;
END$$


-- ============================================================
-- AUDIT TRIGGER 5: Batch insert
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_batch_insert$$
CREATE TRIGGER trg_audit_batch_insert
AFTER INSERT ON Batch
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
    VALUES (
        'Batch',
        'INSERT',
        NEW.batch_id,
        NULL,
        NULL,
        CONCAT('qty=', NEW.quantity, ' unit_cost=', NEW.unit_cost),
        CONCAT('Producer:', NEW.producer_id, ' Product:', NEW.product_id, ' Warehouse:', NEW.warehouse_id)
    );
END$$


-- ============================================================
-- AUDIT TRIGGER 6: Wallet balance change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_wallet$$
CREATE TRIGGER trg_audit_wallet
AFTER UPDATE ON Wallet
FOR EACH ROW
BEGIN
    IF OLD.balance <> NEW.balance THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Wallet',
            'UPDATE',
            NEW.customer_id,
            'balance',
            CAST(OLD.balance AS CHAR),
            CAST(NEW.balance AS CHAR),
            CONCAT('Customer ID: ', NEW.customer_id)
        );
    END IF;
END$$


-- ============================================================
-- AUDIT TRIGGER 7: Restock request status change
-- ============================================================
DROP TRIGGER IF EXISTS trg_audit_restock_status$$
CREATE TRIGGER trg_audit_restock_status
AFTER UPDATE ON Restock_Request
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO Audit_Log (table_name, operation, record_id, changed_field, old_value, new_value, note)
        VALUES (
            'Restock_Request',
            'UPDATE',
            NEW.request_id,
            'status',
            OLD.status,
            NEW.status,
            CONCAT('Producer:', NEW.producer_id, ' Product:', NEW.product_id)
        );
    END IF;
END$$

DELIMITER ;


-- ============================================================
-- VERIFY TRIGGERS
-- ============================================================
SHOW TRIGGERS WHERE `Table` IN (
'Producer','Producer_Product','Order','Batch','Wallet','Restock_Request'
);


-- ============================================================
-- VIEW RECENT AUDIT LOGS
-- ============================================================
SELECT * FROM Audit_Log ORDER BY changed_at DESC LIMIT 20;