-- ============================================================
-- AUTH DATABASE
-- ============================================================

CREATE DATABASE IF NOT EXISTS auth_db;
USE auth_db;

-- ROLES TABLE
CREATE TABLE IF NOT EXISTS roles (
    role_id   INT PRIMARY KEY,
    role_name VARCHAR(20) NOT NULL
);

-- USERS TABLE  (linked_id ties auth user → supplychain entity)
CREATE TABLE IF NOT EXISTS users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id       INT NOT NULL,
    linked_id     INT DEFAULT NULL,          -- FK to Producer / Warehouse / Customer
    FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

-- DEFAULT ROLES
INSERT IGNORE INTO roles VALUES
(1, 'PRODUCER'),
(2, 'ADMIN'),
(3, 'CUSTOMER');