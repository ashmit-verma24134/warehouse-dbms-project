-- Migration: Price Change Approval System
-- Prevents producers from directly updating prices on the customer-facing store.
-- All price changes must be approved by the warehouse admin.

USE supplychain_db;

CREATE TABLE IF NOT EXISTS Price_Change_Request (
    change_id      INT AUTO_INCREMENT PRIMARY KEY,
    producer_id    INT NOT NULL,
    product_id     INT NOT NULL,
    old_price      DECIMAL(10,2) NOT NULL,
    new_price      DECIMAL(10,2) NOT NULL,
    status         ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at    TIMESTAMP NULL,
    admin_note     VARCHAR(255) NULL,
    FOREIGN KEY (producer_id) REFERENCES Producer(producer_id),
    FOREIGN KEY (product_id)  REFERENCES Product(product_id),
    CHECK (new_price > 0),
    CHECK (old_price > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_pcr_status ON Price_Change_Request(status);
CREATE INDEX idx_pcr_producer ON Price_Change_Request(producer_id);
