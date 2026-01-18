-- =============================================================================
-- Customer Onboarding Workflow - Complete PostgreSQL 18 Schema
-- Supports Kafka → CAF → Pre-activation → Tele-verification → Final Activation → Commission
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Create dedicated schema
DROP SCHEMA IF EXISTS onboarding CASCADE;
CREATE SCHEMA onboarding;

-- =============================================================================
-- 1. ZONE CONFIGURATION (Step 3,5,7,9 - Zone-based integration modes)
-- =============================================================================
CREATE TABLE onboarding.zone_config (
    id BIGSERIAL PRIMARY KEY,
    zone_code VARCHAR(10) NOT NULL UNIQUE CHECK (zone_code IN ('NORTH', 'SOUTH', 'EAST', 'WEST')),
    zone_name VARCHAR(50) NOT NULL,
    
    -- Integration modes for each step
    pre_activation_mode VARCHAR(10) NOT NULL CHECK (pre_activation_mode IN ('API', 'DB_LINK')),
    televerification_mode VARCHAR(10) NOT NULL CHECK (televerification_mode IN ('API', 'DB_LINK')),
    final_activation_mode VARCHAR(10) NOT NULL CHECK (final_activation_mode IN ('API', 'DB_LINK')),
    commission_mode VARCHAR(10) NOT NULL CHECK (commission_mode IN ('API', 'DB_LINK')),
    
    -- Callback URLs
    pre_activation_callback TEXT,
    televerification_callback TEXT,
    final_activation_callback TEXT,
    commission_callback TEXT,
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 2. AGENT/CSC MAPPING (Zone determination)
-- =============================================================================
CREATE TABLE onboarding.agent_zone_map (
    id BIGSERIAL PRIMARY KEY,
    hrno VARCHAR(50) NOT NULL UNIQUE,
    agent_name VARCHAR(100),
    zone_code VARCHAR(10) NOT NULL REFERENCES onboarding.zone_config(zone_code) ON DELETE RESTRICT,
    agent_type VARCHAR(20) CHECK (agent_type IN ('POS_AGENT', 'CSC')),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 3. MAIN CAF TABLE (Step 1 - Kafka Record Entry)
-- =============================================================================
CREATE TABLE onboarding.caf (
    id BIGSERIAL PRIMARY KEY,
    
    -- Kafka identifiers
    kafka_message_id VARCHAR(100) UNIQUE NOT NULL,
    kafka_topic VARCHAR(100) DEFAULT 'caf-submission',
    kafka_partition INTEGER,
    kafka_offset BIGINT,
    
    -- Core business data
    plan_code VARCHAR(20) NOT NULL,
    imsi VARCHAR(20),
    permanent_imsi VARCHAR(20),
    customer_name VARCHAR(100) NOT NULL,
    customer_phone VARCHAR(15),
    
    -- Agent/Channel info
    pos_agent_hrno VARCHAR(50) REFERENCES onboarding.agent_zone_map(hrno),
    csc_hrno VARCHAR(50) REFERENCES onboarding.agent_zone_map(hrno),
    zone_code VARCHAR(10) REFERENCES onboarding.zone_config(zone_code),
    
    -- Workflow status (tracks all 9 steps)
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_KAFKA_VALIDATION'
        CHECK (status IN (
            'PENDING_KAFKA_VALIDATION',
            'VALIDATED_IMSI',
            'PENDING_CSC_APPROVAL',
            'CSC_APPROVED',
            'CSC_REJECTED',
            'PRE_ACTIVATION_PENDING',
            'PRE_ACTIVATION_SUCCESS',
            'PRE_ACTIVATION_FAILED',
            'TELE_VERIFICATION_PENDING',
            'TELE_VERIFICATION_SUCCESS',
            'TELE_VERIFICATION_FAILED',
            'FINAL_ACTIVATION_PENDING',
            'FINAL_ACTIVATION_SUCCESS',
            'FINAL_ACTIVATION_FAILED',
            'COMMISSION_PENDING',
            'COMMISSION_SUCCESS',
            'COMMISSION_FAILED',
            'COMPLETED',
            'FAILED'
        )),
    
    -- Raw Kafka data
    request_data JSONB,
    raw_kafka_message JSONB,
    
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE
);

-- =============================================================================
-- 4. CSC APPROVAL TRACKING (Step 2)
-- =============================================================================
CREATE TABLE onboarding.csc_approval (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT NOT NULL REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    approver_hrno VARCHAR(50) NOT NULL,
    approval_status VARCHAR(20) NOT NULL CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    rejection_reason TEXT,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(caf_id)
);

-- =============================================================================
-- 5. PRE-ACTIVATION STATUS (Steps 3-4)
-- =============================================================================
CREATE TABLE onboarding.pre_activation_status (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT NOT NULL REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    zone_code VARCHAR(10),
    integration_mode VARCHAR(10) CHECK (integration_mode IN ('API', 'DB_LINK')),
    transaction_id VARCHAR(100),
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'TIMEOUT')),
    response_data JSONB,
    error_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(caf_id)
);

-- =============================================================================
-- 6. TELEVERIFICATION STATUS (Steps 5-6)
-- =============================================================================
CREATE TABLE onboarding.televerification_status (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT NOT NULL REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    zone_code VARCHAR(10),
    integration_mode VARCHAR(10) CHECK (integration_mode IN ('API', 'DB_LINK')),
    verification_call_id VARCHAR(100),
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'CUSTOMER_UNREACHABLE', 'TIMEOUT')),
    response_data JSONB,
    error_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(caf_id)
);

-- =============================================================================
-- 7. FINAL ACTIVATION STATUS (Steps 7-8)
-- =============================================================================
CREATE TABLE onboarding.final_activation_status (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT NOT NULL REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    zone_code VARCHAR(10),
    integration_mode VARCHAR(10) CHECK (integration_mode IN ('API', 'DB_LINK')),
    transaction_id VARCHAR(100),
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'TIMEOUT')),
    response_data JSONB,
    error_message TEXT,
    activation_number VARCHAR(20),  -- Final activated number
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(caf_id)
);

-- =============================================================================
-- 8. COMMISSION SETTLEMENT (Step 9 - Agent only)
-- =============================================================================
CREATE TABLE onboarding.commission_status (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT NOT NULL REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    zone_code VARCHAR(10),
    integration_mode VARCHAR(10) CHECK (integration_mode IN ('API', 'DB_LINK')),
    agent_hrno VARCHAR(50),
    commission_amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED', 'NO_COMMISSION')),
    sancharsoft_txn_id VARCHAR(100),
    response_data JSONB,
    error_message TEXT,
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(caf_id)
);

-- =============================================================================
-- 9. AUDIT LOG (Complete workflow tracking)
-- =============================================================================
CREATE TABLE onboarding.workflow_audit (
    id BIGSERIAL PRIMARY KEY,
    caf_id BIGINT REFERENCES onboarding.caf(id) ON DELETE SET NULL,
    step_number INTEGER CHECK (step_number BETWEEN 1 AND 9),
    step_name VARCHAR(50),
    status VARCHAR(20),
    details JSONB,
    executed_by VARCHAR(100) DEFAULT 'SYSTEM',
    execution_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- SAMPLE DATA INSERTION
-- =============================================================================

-- Insert Zone Configurations (Step 3,5,7,9)
INSERT INTO onboarding.zone_config (zone_code, zone_name, pre_activation_mode, televerification_mode, final_activation_mode, commission_mode, pre_activation_callback) VALUES
('NORTH', 'North Zone', 'API', 'DB_LINK', 'API', 'API', 'http://billing.north/callback/preact'),
('SOUTH', 'South Zone', 'DB_LINK', 'API', 'DB_LINK', 'API', 'http://billing.south/callback/preact'),
('EAST',  'East Zone', 'API', 'API', 'API', 'DB_LINK', 'http://billing.east/callback/preact'),
('WEST',  'West Zone', 'DB_LINK', 'DB_LINK', 'API', 'API', 'http://billing.west/callback/preact');

-- Insert Agent/CSC Mappings
INSERT INTO onboarding.agent_zone_map (hrno, agent_name, zone_code, agent_type) VALUES
('HR001', 'North POS Agent 1', 'NORTH', 'POS_AGENT'),
('HR002', 'South POS Agent 1', 'SOUTH', 'POS_AGENT'),
('HR003', 'East POS Agent 1', 'EAST', 'POS_AGENT'),
('HR004', 'West POS Agent 1', 'WEST', 'POS_AGENT'),
('CSC001', 'North CSC Approver', 'NORTH', 'CSC'),
('CSC002', 'South CSC Approver', 'SOUTH', 'CSC');

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================
CREATE INDEX CONCURRENTLY idx_caf_status ON onboarding.caf(status);
CREATE INDEX CONCURRENTLY idx_caf_zone ON onboarding.caf(zone_code);
CREATE INDEX CONCURRENTLY idx_caf_kafka_id ON onboarding.caf(kafka_message_id);
CREATE INDEX CONCURRENTLY idx_caf_plan ON onboarding.caf(plan_code);
CREATE INDEX CONCURRENTLY idx_caf_agent ON onboarding.caf(pos_agent_hrno);
CREATE INDEX CONCURRENTLY idx_caf_timestamp ON onboarding.caf(created_at);

CREATE INDEX CONCURRENTLY idx_pre_act_caf ON onboarding.pre_activation_status(caf_id);
CREATE INDEX CONCURRENTLY idx_tele_ver_caf ON onboarding.televerification_status(caf_id);
CREATE INDEX CONCURRENTLY idx_final_act_caf ON onboarding.final_activation_status(caf_id);
CREATE INDEX CONCURRENTLY idx_comm_caf ON onboarding.commission_status(caf_id);

-- JSONB indexes for fast queries
CREATE INDEX CONCURRENTLY idx_caf_request_data_gin ON onboarding.caf USING GIN (request_data);
CREATE INDEX CONCURRENTLY idx_caf_raw_kafka_gin ON onboarding.caf USING GIN (raw_kafka_message);

-- Partial indexes for active records
CREATE INDEX CONCURRENTLY idx_caf_active ON onboarding.caf(status) 
WHERE status IN ('PENDING_KAFKA_VALIDATION', 'PENDING_CSC_APPROVAL', 'PRE_ACTIVATION_PENDING');

-- =============================================================================
-- FUNCTIONS & TRIGGERS
-- =============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION onboarding.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply to all main tables
CREATE TRIGGER update_caf_updated_at BEFORE UPDATE ON onboarding.caf
    FOR EACH ROW EXECUTE FUNCTION onboarding.update_updated_at_column();

CREATE TRIGGER update_zone_updated_at BEFORE UPDATE ON onboarding.zone_config
    FOR EACH ROW EXECUTE FUNCTION onboarding.update_updated_at_column();

-- Audit trail trigger
CREATE OR REPLACE FUNCTION onboarding.log_workflow_step()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO onboarding.workflow_audit (caf_id, step_number, step_name, status, details, executed_by)
    VALUES (
        CASE WHEN TG_TABLE_NAME = 'caf' THEN NEW.id ELSE NULL END,
        CASE 
            WHEN NEW.status LIKE 'PENDING_KAFKA_VALIDATION%' THEN 1
            WHEN NEW.status LIKE 'PENDING_CSC_APPROVAL%' THEN 2
            WHEN NEW.status LIKE 'PRE_ACTIVATION%' THEN 3
            WHEN NEW.status LIKE 'TELE_VERIFICATION%' THEN 5
            WHEN NEW.status LIKE 'FINAL_ACTIVATION%' THEN 7
            WHEN NEW.status LIKE 'COMMISSION%' THEN 9
            ELSE NULL
        END,
        CASE 
            WHEN NEW.status LIKE '%KAFKA%' THEN 'CAF Validation'
            WHEN NEW.status LIKE '%CSC%' THEN 'CSC Approval'
            WHEN NEW.status LIKE '%PRE%' THEN 'Pre-activation'
            WHEN NEW.status LIKE '%TELE%' THEN 'Tele-verification'
            WHEN NEW.status LIKE '%FINAL%' THEN 'Final Activation'
            WHEN NEW.status LIKE '%COMMISSION%' THEN 'Commission'
        END,
        NEW.status,
        jsonb_build_object('caf_id', NEW.id, 'status', NEW.status),
        'SYSTEM'
    );
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER caf_workflow_audit AFTER UPDATE OF status ON onboarding.caf
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION onboarding.log_workflow_step();

-- =============================================================================
-- VIEWS FOR MONITORING
-- =============================================================================

-- Current workflow status dashboard
CREATE VIEW onboarding.workflow_dashboard AS
SELECT 
    c.id,
    c.kafka_message_id,
    c.customer_name,
    c.status,
    c.zone_code,
    c.created_at,
    pa.status as pre_act_status,
    tv.status as tele_ver_status,
    fa.status as final_act_status,
    cs.status as comm_status
FROM onboarding.caf c
LEFT JOIN onboarding.pre_activation_status pa ON c.id = pa.caf_id
LEFT JOIN onboarding.televerification_status tv ON c.id = tv.caf_id
LEFT JOIN onboarding.final_activation_status fa ON c.id = fa.caf_id
LEFT JOIN onboarding.commission_status cs ON c.id = cs.caf_id
WHERE c.status NOT IN ('COMPLETED', 'FAILED', 'CSC_REJECTED');

-- Success rate analytics
CREATE VIEW onboarding.success_metrics AS
SELECT 
    zone_code,
    COUNT(*) as total_requests,
    COUNT(*) FILTER (WHERE status = 'COMPLETED') as successful,
    COUNT(*) FILTER (WHERE status LIKE '%FAILED%' OR status LIKE '%REJECTED%') as failed,
    ROUND((COUNT(*) FILTER (WHERE status = 'COMPLETED')::FLOAT / COUNT(*) * 100), 2) as success_rate
FROM onboarding.caf 
WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY zone_code;

-- =============================================================================
-- GRANTS
-- =============================================================================
GRANT USAGE ON SCHEMA onboarding TO PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA onboarding TO PUBLIC;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA onboarding TO application_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA onboarding TO application_user;

-- =============================================================================
-- EXECUTION SUMMARY
-- =============================================================================
COMMENT ON SCHEMA onboarding IS 'Complete Customer Onboarding Workflow Schema - Supports 9-step process with zone-based integrations';
SELECT '✅ Schema created successfully for Customer Onboarding Workflow (9 steps)' AS status;
SELECT COUNT(*) as tables_created FROM pg_tables WHERE schemaname = 'onboarding';
