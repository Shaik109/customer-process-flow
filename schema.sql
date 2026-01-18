-- PostgreSQL 18 Schema for Customer Onboarding Workflow
CREATE SCHEMA onboarding;

-- Zone Configuration Table
CREATE TABLE onboarding.zone_config (
    id SERIAL PRIMARY KEY,
    zone_code VARCHAR(10) NOT NULL UNIQUE,
    pre_activation_mode VARCHAR(10) CHECK (pre_activation_mode IN ('API', 'DB_LINK')),
    televerification_mode VARCHAR(10) CHECK (televerification_mode IN ('API', 'DB_LINK')),
    final_activation_mode VARCHAR(10) CHECK (final_activation_mode IN ('API', 'DB_LINK')),
    commission_mode VARCHAR(10) CHECK (commission_mode IN ('API', 'DB_LINK')),
    callback_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CAF Table (Customer Application Form)
CREATE TABLE onboarding.caf (
    id SERIAL PRIMARY KEY,
    kafka_message_id VARCHAR(50) UNIQUE,
    plan_code VARCHAR(20) NOT NULL,
    imsi VARCHAR(20),
    permanent_imsi VARCHAR(20),
    pos_agent_hrno VARCHAR(50),
    csc_hrno VARCHAR(50),
    zone_code VARCHAR(10),
    customer_name VARCHAR(100),
    customer_phone VARCHAR(15),
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'VALIDATED', 'APPROVED', 'REJECTED', 'PRE_ACTIVATED', 'TELE_VERIFIED', 'ACTIVATED', 'FAILED')),
    request_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pre-activation Status Table
CREATE TABLE onboarding.pre_activation_status (
    id SERIAL PRIMARY KEY,
    caf_id INTEGER REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    status VARCHAR(20) CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED')),
    response_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Televerification Status Table
CREATE TABLE onboarding.televerification_status (
    id SERIAL PRIMARY KEY,
    caf_id INTEGER REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    status VARCHAR(20) CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED')),
    response_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Final Activation Status Table
CREATE TABLE onboarding.final_activation_status (
    id SERIAL PRIMARY KEY,
    caf_id INTEGER REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    status VARCHAR(20) CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED')),
    response_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Commission Status Table
CREATE TABLE onboarding.commission_status (
    id SERIAL PRIMARY KEY,
    caf_id INTEGER REFERENCES onboarding.caf(id) ON DELETE CASCADE,
    status VARCHAR(20) CHECK (status IN ('PENDING', 'SUCCESS', 'FAILED')),
    response_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert Sample Data
INSERT INTO onboarding.zone_config (zone_code, pre_activation_mode, televerification_mode, final_activation_mode, commission_mode, callback_url) VALUES
('NORTH', 'API', 'DB_LINK', 'API', 'API', 'http://localhost:8080/callback/preact'),
('SOUTH', 'DB_LINK', 'API', 'DB_LINK', 'API', 'http://localhost:8080/callback/telver'),
('EAST', 'API', 'API', 'API', 'DB_LINK', 'http://localhost:8080/callback/finalact'),
('WEST', 'DB_LINK', 'DB_LINK', 'API', 'API', 'http://localhost:8080/callback/commission');

-- Indexes for Performance
CREATE INDEX idx_caf_status ON onboarding.caf(status);
CREATE INDEX idx_caf_zone ON onboarding.caf(zone_code);
CREATE INDEX idx_caf_plan ON onboarding.caf(plan_code);
