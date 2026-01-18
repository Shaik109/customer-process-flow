// service/onboarding_service.go
package service

import (
	"context"
	"customer-onboarding-workflow/models"
	"customer-onboarding-workflow/repository"
	"fmt"
)

type OnboardingService struct {
	cafRepo   *repository.CAFRepository
	zoneRepo  *repository.ZoneRepository
	agentRepo *repository.AgentRepository
	// Add other repos...
}

func NewOnboardingService(
	cafRepo *repository.CAFRepository,
	zoneRepo *repository.ZoneRepository,
	agentRepo *repository.AgentRepository,
) *OnboardingService {
	return &OnboardingService{
		cafRepo:   cafRepo,
		zoneRepo:  zoneRepo,
		agentRepo: agentRepo,
	}
}

// Step 1: Process Kafka CAF Record
func (s *OnboardingService) ProcessKafkaCAF(ctx context.Context, kafkaMsg models.KafkaMessage) (int64, error) {
	// Validate USIM/Non-USIM and get IMSI
	finalIMSI := kafkaMsg.IMSI
	if s.isUSIMPlan(kafkaMsg.PlanCode) {
		finalIMSI = s.fetchPermanentIMSI(kafkaMsg.IMSI)
	}

	// Get Zone from Agent HRNO
	zoneCode, err := s.getZoneFromAgent(ctx, kafkaMsg.PosAgentHRNO)
	if err != nil {
		zoneCode = "NORTH" // Default
	}

	// Create CAF record
	caf := &models.CAF{
		KafkaMessageID:  kafkaMsg.MessageID,
		KafkaTopic:      "caf-submission",
		PlanCode:        kafkaMsg.PlanCode,
		IMSI:            &kafkaMsg.IMSI,
		PermanentIMSI:   &finalIMSI,
		CustomerName:    kafkaMsg.CustomerName,
		CustomerPhone:   &kafkaMsg.CustomerPhone,
		PosAgentHRNO:    &kafkaMsg.PosAgentHRNO,
		CSCHRNO:         &kafkaMsg.CSCHRNO,
		ZoneCode:        &zoneCode,
		Status:          "PENDING_KAFKA_VALIDATION",
		RequestData:     kafkaMsg.RequestData,
		RawKafkaMessage: kafkaMsg.RawMessage,
	}

	cafID, err := s.cafRepo.Create(ctx, caf)
	if err != nil {
		return 0, fmt.Errorf("failed to create CAF: %w", err)
	}

	// Update to validated status
	err = s.cafRepo.UpdateStatus(ctx, cafID, "VALIDATED_IMSI")
	return cafID, err
}

// Step 2: CSC Approval
func (s *OnboardingService) CSCApproval(ctx context.Context, cafID int64, approved bool, approverHRNO string) error {
	newStatus := "CSC_APPROVED"
	if !approved {
		newStatus = "CSC_REJECTED"
	}

	err := s.cafRepo.UpdateStatus(ctx, cafID, newStatus)
	if err != nil {
		return err
	}

	// Record approval
	approval := &models.CSCApproval{
		CafID:          cafID,
		ApproverHRNO:   approverHRNO,
		ApprovalStatus: newStatus,
	}

	return s.cscRepo.Create(ctx, approval)
}

// Step 3-4: Pre-activation
func (s *OnboardingService) PreActivation(ctx context.Context, cafID int64) error {
	caf, err := s.cafRepo.GetByID(ctx, cafID)
	if err != nil {
		return err
	}

	zoneConfig, _ := s.zoneRepo.GetByZoneCode(ctx, *caf.ZoneCode)

	preActStatus := &models.PreActivationStatus{
		CafID:           cafID,
		ZoneCode:        caf.ZoneCode,
		IntegrationMode: zoneConfig.PreActivationMode,
		Status:          "PENDING",
	}

	if zoneConfig.PreActivationMode == "API" {
		// Call API
		go s.callPreActivationAPI(ctx, preActStatus)
	} else {
		// DB Link
		s.insertPreActivationDB(ctx, preActStatus)
	}

	return s.preActRepo.Create(ctx, preActStatus)
}

// Step 5-6: Tele-verification (similar pattern)
func (s *OnboardingService) TeleVerification(ctx context.Context, cafID int64) error {
	// Implementation similar to PreActivation
	return nil
}

// Step 7-8: Final Activation (similar pattern)
func (s *OnboardingService) FinalActivation(ctx context.Context, cafID int64) error {
	// Implementation similar to PreActivation
	return nil
}

// Step 9: Commission Settlement
func (s *OnboardingService) CommissionSettlement(ctx context.Context, cafID int64) error {
	caf, err := s.cafRepo.GetByID(ctx, cafID)
	if err != nil {
		return err
	}

	// Only for POS Agent initiated requests
	if caf.PosAgentHRNO == nil {
		return s.cafRepo.UpdateStatus(ctx, cafID, "COMPLETED")
	}

	zoneConfig, _ := s.zoneRepo.GetByZoneCode(ctx, *caf.ZoneCode)
	commissionStatus := &models.CommissionStatus{
		CafID:           cafID,
		ZoneCode:        caf.ZoneCode,
		AgentHRNO:       caf.PosAgentHRNO,
		IntegrationMode: zoneConfig.CommissionMode,
		Status:          "PENDING",
	}

	if zoneConfig.CommissionMode == "API" {
		go s.callSancharsoftAPI(ctx, commissionStatus)
	} else {
		s.insertCommissionDB(ctx, commissionStatus)
	}

	return s.commRepo.Create(ctx, commissionStatus)
}

func (s *OnboardingService) isUSIMPlan(planCode string) bool {
	usimPlans := map[string]bool{
		"USIM001": true, "USIM002": true, "USIM003": true,
	}
	return usimPlans[planCode]
}

func (s *OnboardingService) getZoneFromAgent(ctx context.Context, hrno string) (string, error) {
	agent, err := s.agentRepo.GetByHRNO(ctx, hrno)
	if err != nil {
		return "", err
	}
	return agent.ZoneCode, nil
}
