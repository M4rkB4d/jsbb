-- ================================================================
-- R__procedures.sql
-- AFASA Engine — Stored procedures (Flyway REPEATABLE migration)
--
-- FIX-109 (v2.3.8): SP metadata captures QUOTED_IDENTIFIER and
-- ANSI_NULLS at CREATE time. Setting them explicitly ensures
-- consistent SP behavior regardless of the connection that applied
-- the migration.
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
--
-- REPEATABLE migrations re-run whenever their checksum changes.
-- Procedures use CREATE OR ALTER so they're safe to re-execute.
--
-- 13 procedures total:
--   INSERT (3): AFASA_InsertRequest, AFASA_InsertRequestDetails,
--               AFASA_InsertAuditTrail
--   UPDATE (2): AFASA_UpdateRequest, AFASA_UpdateRequestDetails
--   GET    (5): AFASA_GetRequestIdByTypeCustomerStatus,
--               AFASA_GetRequestDetailsCountToUpdate,
--               AFASA_GetRequestByRequestId,
--               AFASA_GetAFASARequestList,
--               AFASA_GetAuditTrailList
--   RETRY  (2): AFASA_GetReadyForRetryLifts,
--               AFASA_UpdateRetrySchedule
--   LOOKUP (1): AFASA_GetRequestIdByTransactionId  (NEW v2.2 FIX-46;
--               v2.3 FIX-65 added @customer_id parameter)
--
-- Schema state: v2.3.2 (FIX-100 anchors header to v2.3.2; carries
-- forward post-FIX-83 idempotency_key removal. v2.3.2 SP changes:
-- FIX-87 SP10 next_retry_at, FIX-88 SP2 comment, FIX-94 SP1 message
-- normalization, FIX-95 SP13 comment — applied below to mirror
-- AFASA_Storedprocedures.sql.)
-- ================================================================

-- ================================================================
-- INSERT STORED PROCEDURES
-- ================================================================

-- ----------------------------------------------------------------
-- 1. AFASA_InsertRequest
-- v2.3.1 FIX-83: idempotency_key parameter and column write removed.
-- Sole dedup is (correlation_id, request_type) — uq_req_correlation_type.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_InsertRequest
    @request_type     NVARCHAR(5),
    @customer_id      NVARCHAR(50),
    @status           NVARCHAR(30),
    @channel_id       INT,                -- FIX-103 (v2.3.3): stays INT; API contract only changed
    @correlation_id   NVARCHAR(50),
    @requested_at     DATETIME2     = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id              BIGINT;
    DECLARE @rows_affected   INT     = 0;
    DECLARE @error_code      INT     = 200;
    DECLARE @error_message   NVARCHAR(MAX) = 'Successfully inserted AFASA request.';
    DECLARE @existing_id     BIGINT;

    IF @requested_at IS NULL SET @requested_at = SYSUTCDATETIME();

    BEGIN TRY
        SELECT TOP 1 @existing_id = id
        FROM AFASA_Request
        WHERE correlation_id = @correlation_id
          AND request_type   = @request_type;

        IF @existing_id IS NOT NULL
        BEGIN
            SET @id = @existing_id;
            SET @rows_affected = 0;
            -- FIX-94 (v2.3.2): normalized message
            SET @error_message = 'Existing request returned (dedup replay).';
        END
        ELSE
        BEGIN
            INSERT INTO AFASA_Request (
                request_type, customer_id, [status], channel_id,
                correlation_id, requested_at, updated_at
            )
            VALUES (
                @request_type, @customer_id, @status, @channel_id,
                @correlation_id, @requested_at, @requested_at
            );

            -- FIX-70: @@ROWCOUNT first, SCOPE_IDENTITY second
            SET @rows_affected = @@ROWCOUNT;
            SET @id            = SCOPE_IDENTITY();
        END
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2627, 2601)
        BEGIN
            SELECT TOP 1 @id = id FROM AFASA_Request
            WHERE correlation_id = @correlation_id
              AND request_type   = @request_type;

            IF @id IS NOT NULL
            BEGIN
                SET @rows_affected = 0;
                SET @error_code = 200;
                -- FIX-94 (v2.3.2): normalized message
                SET @error_message = 'Existing request returned (dedup replay).';
            END
            ELSE
            BEGIN
                SET @id = -1;
                SET @error_code = 500;
                SET @error_message = 'UNIQUE violation but no matching row located — investigate.';
            END
        END
        ELSE
        BEGIN
            SET @id = -1;
            SET @rows_affected = 0;
            SET @error_code = 500;
            SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
        END
    END CATCH

    SELECT @id AS id, @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ----------------------------------------------------------------
-- 2. AFASA_InsertRequestDetails
--
-- @decision values per workflow:
--   THF, ML: 'ACCEPTED' or 'REJECTED' (validated by trigger 5)
--   TPP, KS: 'EXECUTED' (FIX-53 convention; trigger does not check)
--
-- FIX-79: failure cases write only Request + AuditTrail rows
-- (no Details row) per the v2.2 working-assumptions table.
--
-- FIX-88 (v2.3.2): @next_retry_at is INTENTIONALLY excluded from the
-- parameter list — set after EAPI response via SP12.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_InsertRequestDetails
    @request_id      BIGINT,
    @store_code      NVARCHAR(15)   = NULL,
    @account_number  NVARCHAR(25),
    @amount          DECIMAL(19,2)  = NULL,
    @currency        CHAR(3)        = NULL,
    @decision        NVARCHAR(10),
    @reason          NVARCHAR(255)  = NULL,
    @held_at         DATETIME2      = NULL,
    @expiry_at       DATETIME2      = NULL,
    @lifted_at       DATETIME2      = NULL,
    @transaction_id  NVARCHAR(50)   = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id            BIGINT;
    DECLARE @rows_affected INT     = 0;
    DECLARE @error_code    INT     = 200;
    DECLARE @error_message NVARCHAR(MAX) = 'Successfully inserted AFASA request details.';
    DECLARE @existing_id   BIGINT;

    BEGIN TRY
        SELECT TOP 1 @existing_id = id
        FROM AFASA_RequestDetails
        WHERE request_id = @request_id;

        IF @existing_id IS NOT NULL
        BEGIN
            SET @id = @existing_id;
            SET @rows_affected = 0;
            SET @error_message = 'Existing details row returned (idempotent replay).';
        END
        ELSE
        BEGIN
            INSERT INTO AFASA_RequestDetails (
                request_id, store_code, account_number, amount, currency,
                decision, reason, held_at, expiry_at, lifted_at, transaction_id
            )
            VALUES (
                @request_id, @store_code, @account_number, @amount, @currency,
                @decision, @reason, @held_at, @expiry_at, @lifted_at, @transaction_id
            );

            -- FIX-70: @@ROWCOUNT first, SCOPE_IDENTITY second
            SET @rows_affected = @@ROWCOUNT;
            SET @id            = SCOPE_IDENTITY();
        END
    END TRY
    BEGIN CATCH
        SET @id = -1;
        SET @rows_affected = 0;
        SET @error_code = 500;
        SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
    END CATCH

    SELECT @id AS id, @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ----------------------------------------------------------------
-- 3. AFASA_InsertAuditTrail
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_InsertAuditTrail
    @request_id    BIGINT,
    @code          INT,
    @message       NVARCHAR(MAX),
    @created_by    NVARCHAR(50),
    @created_at    DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id            BIGINT;
    DECLARE @rows_affected INT     = 0;
    DECLARE @error_code    INT     = 200;
    DECLARE @error_message NVARCHAR(MAX) = 'Successfully inserted AFASA audit trail.';

    IF @created_at IS NULL SET @created_at = SYSUTCDATETIME();

    BEGIN TRY
        INSERT INTO AFASA_AuditTrail (request_id, error_code, error_message, created_by, created_at)
        VALUES (@request_id, @code, @message, @created_by, @created_at);

        -- FIX-70: @@ROWCOUNT first, SCOPE_IDENTITY second
        SET @rows_affected = @@ROWCOUNT;
        SET @id            = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        SET @id = -1;
        SET @rows_affected = 0;
        SET @error_code = 500;
        SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
    END CATCH

    SELECT @id AS id, @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ================================================================
-- UPDATE STORED PROCEDURES
-- ================================================================

-- ----------------------------------------------------------------
-- 4. AFASA_UpdateRequest
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_UpdateRequest
    @request_id  BIGINT,
    @status      NVARCHAR(30),
    @updated_at  DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rows_affected INT     = 0;
    DECLARE @error_code    INT     = 200;
    DECLARE @error_message NVARCHAR(MAX) = 'Successfully updated AFASA request.';

    IF @updated_at IS NULL SET @updated_at = SYSUTCDATETIME();

    BEGIN TRY
        UPDATE AFASA_Request
           SET [status]   = @status,
               updated_at = @updated_at
         WHERE id = @request_id;

        SET @rows_affected = @@ROWCOUNT;

        IF @rows_affected = 0
        BEGIN
            SET @error_code = 404;
            SET @error_message = 'Request not found (id does not exist).';
        END
    END TRY
    BEGIN CATCH
        SET @rows_affected = 0;
        SET @error_code = 500;
        SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
    END CATCH

    SELECT @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ----------------------------------------------------------------
-- 5. AFASA_UpdateRequestDetails
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_UpdateRequestDetails
    @request_id BIGINT,
    @lifted_at  DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rows_affected INT     = 0;
    DECLARE @error_code    INT     = 200;
    DECLARE @error_message NVARCHAR(MAX) = 'Successfully updated AFASA request details.';

    BEGIN TRY
        UPDATE AFASA_RequestDetails
           SET lifted_at = @lifted_at
         WHERE request_id = @request_id;

        SET @rows_affected = @@ROWCOUNT;

        IF @rows_affected = 0
        BEGIN
            SET @error_code = 404;
            SET @error_message = 'Request details not found.';
        END
    END TRY
    BEGIN CATCH
        SET @rows_affected = 0;
        SET @error_code = 500;
        SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
    END CATCH

    SELECT @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ================================================================
-- GET STORED PROCEDURES
-- ================================================================

-- ----------------------------------------------------------------
-- 6. AFASA_GetRequestIdByTypeCustomerStatus (FIX-41)
-- Returns NULL if no match. See Decision 8 in DECISION_MEMO.md
-- for the "TOP 1 ORDER BY updated_at DESC" rationale.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetRequestIdByTypeCustomerStatus
    @request_type  NVARCHAR(5),
    @customer_id   NVARCHAR(50),
    @status        NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @request_id BIGINT = NULL;

    SELECT TOP 1 @request_id = id
    FROM AFASA_Request
    WHERE request_type = @request_type
      AND customer_id  = @customer_id
      AND [status]     = @status
    ORDER BY updated_at DESC;

    SELECT @request_id AS request_id;
END
GO

-- ----------------------------------------------------------------
-- 7. AFASA_GetRequestDetailsCountToUpdate
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetRequestDetailsCountToUpdate
    @request_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @count INT = 0;

    SELECT @count = COUNT(id)
    FROM AFASA_RequestDetails
    WHERE request_id = @request_id;

    SELECT @count AS [count];
END
GO

-- ----------------------------------------------------------------
-- 8. AFASA_GetRequestByRequestId
-- v2.3.1 FIX-83: idempotency_key removed from SELECT.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetRequestByRequestId
    @request_id  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.id AS request_id, r.customer_id, r.request_type, r.[status],
        r.channel_id, r.correlation_id,
        r.requested_at, r.updated_at,
        rd.store_code, rd.account_number, rd.amount, rd.currency,
        rd.held_at, rd.expiry_at, rd.lifted_at, rd.next_retry_at,
        rd.decision, rd.reason, rd.transaction_id
    FROM AFASA_Request r
    LEFT JOIN AFASA_RequestDetails rd ON r.id = rd.request_id
    WHERE r.id = @request_id;
END
GO

-- ----------------------------------------------------------------
-- 9. AFASA_GetAFASARequestList
-- FIX-66 (v2.3): decision filter preserves failure-path rows.
-- FIX-67 (v2.3): includes next_retry_at.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetAFASARequestList
    @request_type  NVARCHAR(5),
    @decision      NVARCHAR(10) = NULL,
    @dateTimeFrom  DATETIME2,
    @dateTimeTo    DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.id AS request_id, r.customer_id, r.request_type, r.[status],
        r.channel_id, r.correlation_id, r.requested_at, r.updated_at,
        rd.store_code, rd.account_number, rd.amount, rd.currency,
        rd.held_at, rd.expiry_at, rd.lifted_at, rd.next_retry_at,
        rd.decision, rd.reason, rd.transaction_id
    FROM AFASA_Request r
    LEFT JOIN AFASA_RequestDetails rd ON r.id = rd.request_id
    WHERE r.request_type = @request_type
      AND (@decision IS NULL
           OR (rd.request_id IS NOT NULL AND rd.decision = @decision))
      AND r.updated_at BETWEEN @dateTimeFrom AND @dateTimeTo
    ORDER BY r.updated_at DESC;
END
GO

-- ----------------------------------------------------------------
-- 10. AFASA_GetAuditTrailList
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetAuditTrailList
    @error_code    INT          = NULL,
    @created_by    NVARCHAR(50) = NULL,
    @dateTimeFrom  DATETIME2,
    @dateTimeTo    DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    -- FIX-87 (v2.3.2): rd.next_retry_at added (mirrors design SP).
    SELECT
        r.id AS request_id, r.customer_id, r.request_type, r.[status],
        r.channel_id, r.correlation_id, r.requested_at, r.updated_at,
        rd.store_code, rd.account_number, rd.amount, rd.currency,
        rd.held_at, rd.expiry_at, rd.lifted_at, rd.next_retry_at,
        rd.decision, rd.reason, rd.transaction_id,
        a.id AS audit_id, a.error_code, a.error_message, a.created_by, a.created_at
    FROM AFASA_Request r
    LEFT JOIN AFASA_RequestDetails rd ON r.id = rd.request_id
    INNER JOIN AFASA_AuditTrail a     ON r.id = a.request_id
    WHERE (@error_code IS NULL OR a.error_code = @error_code)
      AND (@created_by IS NULL OR a.created_by = @created_by)
      AND a.created_at BETWEEN @dateTimeFrom AND @dateTimeTo
    ORDER BY a.created_at DESC;
END
GO

-- ================================================================
-- RETRY/BACKSTOP STORED PROCEDURES
-- ================================================================

-- ----------------------------------------------------------------
-- 11. AFASA_GetReadyForRetryLifts (NEW-1, v2.0)
-- Read-only — Java @Scheduled job iterates and calls EAPI.
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetReadyForRetryLifts
    @cutoff_at  DATETIME2 = NULL,
    @max_rows   INT       = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @cutoff_at IS NULL SET @cutoff_at = SYSUTCDATETIME();

    SELECT TOP (@max_rows)
        r.id AS request_id, r.request_type, r.customer_id, r.correlation_id, r.[status],
        rd.store_code, rd.account_number, rd.transaction_id,
        rd.next_retry_at, rd.expiry_at
    FROM AFASA_Request r
    INNER JOIN AFASA_RequestDetails rd ON rd.request_id = r.id
    WHERE r.[status] IN ('LIFT_FAILED','UNLOCK_FAILED')
      AND rd.next_retry_at IS NOT NULL
      AND rd.next_retry_at <= @cutoff_at
    ORDER BY rd.next_retry_at ASC;
END
GO

-- ----------------------------------------------------------------
-- 12. AFASA_UpdateRetrySchedule (NEW-2, v2.0)
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_UpdateRetrySchedule
    @request_id     BIGINT,
    @next_retry_at  DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @rows_affected INT     = 0;
    DECLARE @error_code    INT     = 200;
    DECLARE @error_message NVARCHAR(MAX) = 'Successfully updated retry schedule.';

    BEGIN TRY
        UPDATE AFASA_RequestDetails
           SET next_retry_at = @next_retry_at
         WHERE request_id = @request_id;

        SET @rows_affected = @@ROWCOUNT;

        IF @rows_affected = 0
        BEGIN
            SET @error_code = 404;
            SET @error_message = 'Request details not found.';
        END
    END TRY
    BEGIN CATCH
        SET @rows_affected = 0;
        SET @error_code = 500;
        SET @error_message = CONCAT('Error:', ERROR_NUMBER(), '|Message:', ERROR_MESSAGE());
    END CATCH

    SELECT @rows_affected AS rows_affected, @error_code AS error_code, @error_message AS error_message;
END
GO

-- ----------------------------------------------------------------
-- 13. AFASA_GetRequestIdByTransactionId (FIX-46 v2.2 + FIX-65 v2.3)
--
-- Resolves ML/THF PATCH endpoint path parameters
--   ({customerId}, {transactionId}) → AFASA_Request.id.
--
-- FIX-65: customer_id parameter is REQUIRED — closes cross-customer
-- lookup leak (same security CLASS as the v2.2 FIX-47 idempotency
-- leak; v2.2 FIX-47 itself is superseded by v2.3.1 FIX-83 — see
-- FIX-95 v2.3.2 for clarification).
--
-- FIX-69: transaction_id is UNIQUE (filtered) — at most one match.
--
-- Returns NULL if no match (caller treats as 404).
-- ----------------------------------------------------------------
CREATE OR ALTER PROCEDURE AFASA_GetRequestIdByTransactionId
    @transaction_id  NVARCHAR(50),
    @request_type    NVARCHAR(5),
    @customer_id     NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @request_id BIGINT = NULL;

    SELECT TOP 1 @request_id = r.id
    FROM AFASA_Request r
    INNER JOIN AFASA_RequestDetails rd ON rd.request_id = r.id
    WHERE rd.transaction_id = @transaction_id
      AND r.request_type    = @request_type
      AND r.customer_id     = @customer_id
    ORDER BY r.updated_at DESC;

    SELECT @request_id AS request_id;
END
GO
