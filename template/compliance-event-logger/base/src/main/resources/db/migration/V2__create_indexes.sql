-- ================================================================
-- V2__create_indexes.sql
-- AFASA Engine — Index creation (Flyway versioned migration)
--
-- FIX-109 (v2.3.8): SET QUOTED_IDENTIFIER ON is REQUIRED for
-- filtered indexes (ix_details_txn_id, ix_details_expiry_sweep,
-- ix_details_retry_sweep, uq_req_idempotency historically). Without
-- this, CREATE INDEX with a WHERE clause fails with error 1934.
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
--
-- V2 follows V1 (tables). Indexes are split into a separate file
-- for review-friendliness and so that index changes don't require
-- re-applying table DDL.
--
-- 13 indexes total:
--   AFASA_Request          — 5 (1 UNIQUE primary dedup, 4 lookup)
--   AFASA_RequestDetails   — 5 (2 UNIQUE, 3 filtered for sweeps)
--   AFASA_AuditTrail       — 3 (lookup support)
--
-- Schema state: v2.3.2 (post FIX-83 — FIX-84 was API contract only,
-- not DDL; per FIX-98 we no longer cite FIX-84 in this DDL header)
--   FIX-83: uq_req_idempotency NOT created (column gone)
--   FIX-69: ix_details_txn_id is UNIQUE (was non-unique in v2.2)
-- ================================================================

-- ----------------------------------------------------------------
-- AFASA_Request indexes (5)
-- ----------------------------------------------------------------

-- PRIMARY DEDUP (FIX-32, v2.1) — sole dedup mechanism after FIX-83.
-- EAPI commits to preserving correlation_id on retries; AFASA dedupes
-- on (correlation_id, request_type) at the DB layer.
CREATE UNIQUE INDEX uq_req_correlation_type
    ON AFASA_Request (correlation_id, request_type);
GO

CREATE INDEX ix_req_type_status
    ON AFASA_Request (request_type, [status]);
GO

CREATE INDEX ix_req_type_customer_id_status
    ON AFASA_Request (request_type, customer_id, [status]);
GO

CREATE INDEX ix_req_correlation
    ON AFASA_Request (correlation_id);
GO

CREATE INDEX ix_req_type_updated_at
    ON AFASA_Request (request_type, updated_at);
GO

-- ----------------------------------------------------------------
-- AFASA_RequestDetails indexes (5)
-- ----------------------------------------------------------------

-- 1:1 enforcement with AFASA_Request
CREATE UNIQUE INDEX ux_details_request
    ON AFASA_RequestDetails (request_id);
GO

CREATE INDEX ix_details_account
    ON AFASA_RequestDetails (account_number);
GO

-- FIX-69 (v2.3): UNIQUE filtered index on transaction_id.
-- transaction_id is unique per ML/THF request by design (T24-issued).
-- Filter excludes TPP/KS rows where transaction_id is NULL.
CREATE UNIQUE INDEX ix_details_txn_id
    ON AFASA_RequestDetails (transaction_id)
    WHERE transaction_id IS NOT NULL;
GO

-- TPP 24h expiry sweep — covering index
CREATE INDEX ix_details_expiry_sweep
    ON AFASA_RequestDetails (expiry_at)
    INCLUDE (request_id)
    WHERE expiry_at IS NOT NULL;
GO

-- LIFT_FAILED backstop sweep — covering index
CREATE INDEX ix_details_retry_sweep
    ON AFASA_RequestDetails (next_retry_at)
    INCLUDE (request_id)
    WHERE next_retry_at IS NOT NULL;
GO

-- ----------------------------------------------------------------
-- AFASA_AuditTrail indexes (3)
-- ----------------------------------------------------------------

CREATE INDEX ix_audit_trail_error_code
    ON AFASA_AuditTrail (error_code);
GO

CREATE INDEX ix_audit_trail_created_at
    ON AFASA_AuditTrail (created_at);
GO

CREATE INDEX ix_audit_trail_request_id
    ON AFASA_AuditTrail (request_id);
GO
