// models/models.go - Database Models
package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"
)

type ZoneConfig struct {
	ID                    int64    `json:"id"`
	ZoneCode              string   `json:"zone_code"`
	ZoneName              string   `json:"zone_name"`
	PreActivationMode     string   `json:"pre_activation_mode"`
	TeleverificationMode  string   `json:"televerification_mode"`
	FinalActivationMode   string   `json:"final_activation_mode"`
	CommissionMode        string   `json:"commission_mode"`
	PreActivationCallback string   `json:"pre_activation_callback"`
	IsActive              bool     `json:"is_active"`
	CreatedAt             TimeTime `json:"created_at"`
	UpdatedAt             TimeTime `json:"updated_at"`
}

type AgentZoneMap struct {
	ID        int64    `json:"id"`
	HRNO      string   `json:"hrno"`
	AgentName string   `json:"agent_name"`
	ZoneCode  string   `json:"zone_code"`
	AgentType string   `json:"agent_type"`
	IsActive  bool     `json:"is_active"`
	CreatedAt TimeTime `json:"created_at"`
}

type CAF struct {
	ID              int64     `json:"id"`
	KafkaMessageID  string    `json:"kafka_message_id"`
	KafkaTopic      string    `json:"kafka_topic"`
	KafkaPartition  *int      `json:"kafka_partition"`
	KafkaOffset     *int64    `json:"kafka_offset"`
	PlanCode        string    `json:"plan_code"`
	IMSI            *string   `json:"imsi"`
	PermanentIMSI   *string   `json:"permanent_imsi"`
	CustomerName    string    `json:"customer_name"`
	CustomerPhone   *string   `json:"customer_phone"`
	PosAgentHRNO    *string   `json:"pos_agent_hrno"`
	CSCHRNO         *string   `json:"csc_hrno"`
	ZoneCode        *string   `json:"zone_code"`
	Status          string    `json:"status"`
	RequestData     JSONB     `json:"request_data"`
	RawKafkaMessage JSONB     `json:"raw_kafka_message"`
	CreatedAt       TimeTime  `json:"created_at"`
	UpdatedAt       TimeTime  `json:"updated_at"`
	ProcessedAt     *TimeTime `json:"processed_at"`
}

type CSCApproval struct {
	ID              int64     `json:"id"`
	CafID           int64     `json:"caf_id"`
	ApproverHRNO    string    `json:"approver_hrno"`
	ApprovalStatus  string    `json:"approval_status"`
	RejectionReason *string   `json:"rejection_reason"`
	ApprovedAt      *TimeTime `json:"approved_at"`
	CreatedAt       TimeTime  `json:"created_at"`
}

type PreActivationStatus struct {
	ID              int64     `json:"id"`
	CafID           int64     `json:"caf_id"`
	ZoneCode        *string   `json:"zone_code"`
	IntegrationMode string    `json:"integration_mode"`
	TransactionID   *string   `json:"transaction_id"`
	Status          string    `json:"status"`
	ResponseData    JSONB     `json:"response_data"`
	ErrorMessage    *string   `json:"error_message"`
	ProcessedAt     *TimeTime `json:"processed_at"`
	CreatedAt       TimeTime  `json:"created_at"`
}

// Similar structs for TeleverificationStatus, FinalActivationStatus, CommissionStatus...

type JSONB map[string]interface{}
type TimeTime time.Time

// Implement sql.Scanner and driver.Valuer for JSONB
func (j JSONB) Value() (driver.Value, error) {
	return json.Marshal(j)
}

func (j *JSONB) Scan(value interface{}) error {
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}
	return json.Unmarshal(bytes, j)
}
