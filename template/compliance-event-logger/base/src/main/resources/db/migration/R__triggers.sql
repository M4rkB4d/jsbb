-- ================================================================
-- R__triggers.sql
-- AFASA Engine — Validation triggers (Flyway REPEATABLE migration)
--
-- FIX-109 (v2.3.8): trigger metadata captures QUOTED_IDENTIFIER
-- and ANSI_NULLS at CREATE time. Setting them explicitly ensures
-- consistent trigger behavior regardless of the connection that
-- applied the migration.
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
--
-- REPEATABLE migrations re-run whenever their checksum changes.
-- Triggers use CREATE OR ALTER so they're safe to re-execute.
-- This pattern lets us iterate on trigger logic without creating
-- a new V-versioned migration file each time.
--
-- 10 triggers total. Error number reference (FIX-35):
--   50001 — Invalid request type
--   50002 — Invalid status for request type
--   50003 — Invalid amount for request type
--   50004 — Invalid currency for request type
--   50005 — Invalid decision for request type
--   50006 — Invalid reason for request type
--   50007 — Invalid expiry_at for TPP (not held_at + 24h)
--   50008 — lifted_at required for terminal-lift status
--   50009 — held_at required for active hold/lock status
--   50010 — transaction_id required for ML/THF
--
-- Schema state: v2.3.2 (post FIX-86 banner update; carries forward
-- all FIX-09 through FIX-71. v2.3.1 was a no-op for triggers — FIX-83
-- and FIX-84 did not touch trigger logic. FIX-100: header line
-- anchored to v2.3.2 for consistency with V1/V2 header style.)
-- ================================================================

-- ----------------------------------------------------------------
-- 1. AFASA_ValidateRequestType — error 50001
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateRequestType
ON AFASA_Request AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted i
        WHERE i.request_type NOT IN ('TPP','THF','ML','KS')
    )
    BEGIN
        THROW 50001, 'Invalid request type', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 2. AFASA_ValidateStatusPerRequestType — error 50002
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateStatusPerRequestType
ON AFASA_Request AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted i
        WHERE
            (i.request_type = 'TPP' AND i.[status] NOT IN ('ACTIVE','LIFTED','CREATE_FAILED','LIFT_FAILED','EXPIRED'))
         OR (i.request_type = 'THF' AND i.[status] NOT IN ('EVALUATED','ON_HOLD','LIFTED','HOLD_FAILED','LIFT_FAILED'))
         OR (i.request_type = 'ML'  AND i.[status] NOT IN ('LOCKED','UNLOCKED','LOCK_FAILED','UNLOCK_FAILED'))
         OR (i.request_type = 'KS'  AND i.[status] NOT IN ('LOCKED','UNLOCKED','LOCK_FAILED','UNLOCK_FAILED'))
    )
    BEGIN
        THROW 50002, 'Invalid status for request type', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 3. AFASA_ValidateAmountPerRequestType — error 50003
-- FIX-48 (v2.2): Exemption narrowed to LOCK_FAILED, HOLD_FAILED only.
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateAmountPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE r.request_type IN ('THF','ML')
          AND r.[status]    NOT IN ('LOCK_FAILED','HOLD_FAILED')
          AND ISNULL(i.amount, 0) <= 0
    )
    BEGIN
        THROW 50003, 'Invalid amount for request type', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 4. AFASA_ValidateCurrencyPerRequestType — error 50004
-- FIX-49 (v2.2): LTRIM/RTRIM + ISO 4217 alpha-3 LIKE.
-- FIX-71 (v2.3): comment clarified for CHAR(3) semantics.
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateCurrencyPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE r.request_type IN ('THF','ML')
          AND r.[status]    NOT IN ('LOCK_FAILED','HOLD_FAILED')
          AND (
                ISNULL(LTRIM(RTRIM(i.currency)), '') = ''
             OR i.currency COLLATE Latin1_General_BIN NOT LIKE '[A-Z][A-Z][A-Z]'      -- FIX-110: BINARY collation (CS_AS doesn't make LIKE character-classes case-sensitive)
          )
    )
    BEGIN
        THROW 50004, 'Invalid currency for request type (must be ISO 4217 alpha-3, uppercase)', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 5. AFASA_ValidateDecisionPerRequestType — error 50005
-- Scoped to THF/ML only; TPP/KS use 'EXECUTED' convention (FIX-53).
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateDecisionPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE r.request_type IN ('THF','ML')
          AND (ISNULL(i.decision, '') = '' OR i.decision NOT IN ('ACCEPTED','REJECTED'))
    )
    BEGIN
        THROW 50005, 'Invalid decision for request type (must be ACCEPTED or REJECTED for THF/ML)', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 6. AFASA_ValidateReasonPerRequestType — error 50006
-- FIX-68 (v2.3): KS intentionally omitted (no business requirement).
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateReasonPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE
            (r.request_type = 'TPP'
                AND (ISNULL(i.reason, '') = '' OR i.reason NOT IN ('1','2','3')))
         OR (r.request_type IN ('THF','ML')
                AND ISNULL(i.reason, '') = '')
         -- KS: no validation per FIX-68
    )
    BEGIN
        THROW 50006, 'Invalid reason for request type', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 7. AFASA_ValidateExpiryAtPerRequestType — error 50007
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateExpiryAtPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE r.request_type = 'TPP'
          AND i.held_at   IS NOT NULL
          AND i.expiry_at IS NOT NULL
          AND DATEDIFF(MINUTE, i.held_at, i.expiry_at) <> 1440
    )
    BEGIN
        THROW 50007, 'Invalid expiry_at for TPP (must be held_at + 24 hours)', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 8. AFASA_ValidateLiftedAtPerRequestTypeStatusDecision — error 50008
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateLiftedAtPerRequestTypeStatusDecision
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE
            (
                (r.request_type IN ('TPP','THF') AND r.[status] = 'LIFTED')
             OR (r.request_type IN ('ML','KS')  AND r.[status] = 'UNLOCKED')
            )
          AND i.lifted_at IS NULL
    )
    BEGIN
        THROW 50008, 'lifted_at is required when status indicates a successful lift/unlock', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 9. AFASA_ValidateHeldAtPerRequestTypeStatusDecision — error 50009
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateHeldAtPerRequestTypeStatusDecision
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE
            (
                (r.request_type = 'TPP'        AND r.[status] = 'ACTIVE')
             OR (r.request_type = 'THF'        AND r.[status] = 'ON_HOLD')
             OR (r.request_type IN ('ML','KS') AND r.[status] = 'LOCKED')
            )
          AND i.held_at IS NULL
    )
    BEGIN
        THROW 50009, 'held_at is required when status indicates an active hold/lock', 1;
    END
END
GO

-- ----------------------------------------------------------------
-- 10. AFASA_ValidateTransactionIdPerRequestType — error 50010
-- FIX-48: exemption narrowed to LOCK_FAILED/HOLD_FAILED.
-- FIX-52: pattern aligned to (IS NULL OR LEN=0).
-- ----------------------------------------------------------------
CREATE OR ALTER TRIGGER AFASA_ValidateTransactionIdPerRequestType
ON AFASA_RequestDetails AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN AFASA_Request r ON r.id = i.request_id
        WHERE r.request_type IN ('ML','THF')
          AND r.[status]    NOT IN ('LOCK_FAILED','HOLD_FAILED')
          AND (i.transaction_id IS NULL OR LEN(i.transaction_id) = 0)
    )
    BEGIN
        THROW 50010, 'Invalid transaction_id for request type (required for ML/THF on success path)', 1;
    END
END
GO
