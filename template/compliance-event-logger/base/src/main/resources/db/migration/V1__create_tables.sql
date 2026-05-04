-- ================================================================
-- V1__create_tables.sql
-- AFASA Engine — Initial table creation (Flyway versioned migration)
--
-- FIX-109 (v2.3.8): SET options required for filtered indexes (V2)
-- and for trigger/SP metadata. The Microsoft JDBC driver used by
-- Flyway defaults QUOTED_IDENTIFIER=true, but we set explicitly so
-- the same files work via sqlcmd, SSMS, or any other client.
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
--
-- This is V1: creates the four base tables. Indexes are in V2;
-- triggers and stored procedures are in R__ repeatable migrations
-- so that they can be iterated on without bumping the V-version.
--
-- IDEMPOTENCY: This file does NOT use IF NOT EXISTS guards.
-- Flyway's flyway_schema_history table tracks executed migrations;
-- this file runs exactly once per database. If you need to re-create
-- the schema in dev, use Flyway's `clean` (with caution) or drop
-- the AFASA_* tables manually.
--
-- Schema state: v2.3.3
-- - FIX-103 (v2.3.3): channel_id stays INT in DB; API contract only changed
-- - FIX-83 (v2.3.1): idempotency_key column NOT present
-- - FIX-69 (v2.3): UNIQUE filtered index on transaction_id (in V2)
-- - FIX-45 (v2.2): NO CASCADE on fk_request_details
-- - FIX-38 (v2.1): NO CASCADE on fk_audit_trail
-- (FIX-84 was API-contract only — no DDL impact, per FIX-98.)
-- ================================================================

-- ----------------------------------------------------------------
-- 1. AFASA_Request — parent, one row per logical request
-- ----------------------------------------------------------------
CREATE TABLE AFASA_Request (
    id                BIGINT          NOT NULL IDENTITY(1,1),
    request_type      NVARCHAR(5)     NOT NULL,
    customer_id       NVARCHAR(50)    NOT NULL,
    [status]          NVARCHAR(30)    NOT NULL,
    -- FIX-103 (v2.3.3): channel_id stays INT here. API contract only
    -- changed (header type integer → string per HTTP semantics).
    -- Java parses string → int via a channel-mapping table.
    channel_id        INT             NOT NULL,
    correlation_id    NVARCHAR(50)    NOT NULL,
    requested_at      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_request PRIMARY KEY (id)
);
GO

-- ----------------------------------------------------------------
-- 2. AFASA_RequestDetails — child, 1:1 with AFASA_Request
--
-- FIX-45 (v2.2): NO CASCADE on FK — operationally significant data
-- (transaction_id, amount, lifecycle timestamps) must survive any
-- accidental request deletes.
-- ----------------------------------------------------------------
CREATE TABLE AFASA_RequestDetails (
    id                BIGINT          NOT NULL IDENTITY(1,1),
    request_id        BIGINT          NOT NULL,
    store_code        NVARCHAR(15)    NULL,
    account_number    NVARCHAR(25)    NOT NULL,
    amount            DECIMAL(19,2)   NULL,
    currency          CHAR(3)         NULL,
    decision          NVARCHAR(10)    NOT NULL,
    -- decision values per workflow (FIX-53):
    --   THF, ML: 'ACCEPTED' or 'REJECTED' (validated by trigger)
    --   TPP, KS: 'EXECUTED' (no EAPI accept/reject semantic)
    reason            NVARCHAR(255)   NULL,
    held_at           DATETIME2       NULL,
    expiry_at         DATETIME2       NULL,
    lifted_at         DATETIME2       NULL,
    transaction_id    NVARCHAR(50)    NULL,
    next_retry_at     DATETIME2       NULL,

    CONSTRAINT pk_request_details PRIMARY KEY (id),
    CONSTRAINT fk_request_details FOREIGN KEY (request_id)
        REFERENCES AFASA_Request(id)
);
GO

-- ----------------------------------------------------------------
-- 3. AFASA_Shedlock — distributed-job coordination (Spring ShedLock)
-- ----------------------------------------------------------------
CREATE TABLE AFASA_Shedlock (
    name              NVARCHAR(64)    NOT NULL PRIMARY KEY,
    lock_until        DATETIME2       NOT NULL,
    locked_at         DATETIME2       NOT NULL,
    locked_by         NVARCHAR(255)   NOT NULL
);
GO

-- ----------------------------------------------------------------
-- 4. AFASA_AuditTrail — append-only event history
--
-- FIX-38 (v2.1): NO CASCADE on FK — audit trail must survive even
-- if a Request row were ever hard-deleted.
-- ----------------------------------------------------------------
CREATE TABLE AFASA_AuditTrail (
    id                BIGINT          NOT NULL IDENTITY(1,1),
    request_id        BIGINT          NOT NULL,
    error_code        INT             NOT NULL,
    error_message     NVARCHAR(MAX)   NOT NULL,
    created_by        NVARCHAR(50)    NOT NULL,
    created_at        DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT pk_audit_trail PRIMARY KEY (id),
    CONSTRAINT fk_audit_trail FOREIGN KEY (request_id)
        REFERENCES AFASA_Request(id)
);
GO
