// repository/caf_repository.go
package repository

import (
	"context"
	"customer-onboarding-workflow/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type CAFRepository struct {
	db *pgxpool.Pool
}

func NewCAFRepository(db *pgxpool.Pool) *CAFRepository {
	return &CAFRepository{db: db}
}

func (r *CAFRepository) Create(ctx context.Context, caf *models.CAF) (int64, error) {
	var id int64
	err := r.db.QueryRow(ctx,
		`INSERT INTO onboarding.caf (
            kafka_message_id, kafka_topic, kafka_partition, kafka_offset,
            plan_code, imsi, permanent_imsi, customer_name, customer_phone,
            pos_agent_hrno, csc_hrno, zone_code, status, request_data, raw_kafka_message
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         RETURNING id`,
		caf.KafkaMessageID, caf.KafkaTopic, caf.KafkaPartition, caf.KafkaOffset,
		caf.PlanCode, caf.IMSI, caf.PermanentIMSI, caf.CustomerName, caf.CustomerPhone,
		caf.PosAgentHRNO, caf.CSCHRNO, caf.ZoneCode, caf.Status, caf.RequestData, caf.RawKafkaMessage,
	).Scan(&id)
	return id, err
}

func (r *CAFRepository) GetByID(ctx context.Context, id int64) (*models.CAF, error) {
	caf := &models.CAF{}
	err := r.db.QueryRow(ctx,
		`SELECT id, kafka_message_id, kafka_topic, kafka_partition, kafka_offset,
                plan_code, imsi, permanent_imsi, customer_name, customer_phone,
                pos_agent_hrno, csc_hrno, zone_code, status, request_data, raw_kafka_message,
                created_at, updated_at, processed_at
         FROM onboarding.caf WHERE id = $1`, id,
	).Scan(
		&caf.ID, &caf.KafkaMessageID, &caf.KafkaTopic, &caf.KafkaPartition, &caf.KafkaOffset,
		&caf.PlanCode, &caf.IMSI, &caf.PermanentIMSI, &caf.CustomerName, &caf.CustomerPhone,
		&caf.PosAgentHRNO, &caf.CSCHRNO, &caf.ZoneCode, &caf.Status, &caf.RequestData, &caf.RawKafkaMessage,
		&caf.CreatedAt, &caf.UpdatedAt, &caf.ProcessedAt,
	)
	return caf, err
}

func (r *CAFRepository) UpdateStatus(ctx context.Context, id int64, status string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE onboarding.caf SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`,
		status, id)
	return err
}
