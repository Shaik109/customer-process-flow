package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.flowable.io/flowable"
	"go.flowable.io/flowable/client"
)

type App struct {
	db         *pgxpool.Pool
	flowable   *flowable.Client
	httpServer *http.Server
}

type KafkaMessage struct {
	ID        string                 `json:"message_id"`
	PlanCode  string                 `json:"plan_code"`
	IMSI      string                 `json:"imsi"`
	Customer  map[string]interface{} `json:"customer"`
	AgentHRNO string                 `json:"pos_agent_hrno"`
	CSCHRNO   string                 `json:"csc_hrno"`
}

func main() {
	app := &App{}

	// Initialize Database
	dbURL := "postgres://postgres:password@localhost:5432/postgres?sslmode=disable"
	dbpool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	app.db = dbpool

	// Initialize Flowable
	flowableClient, err := flowable.NewClient(&client.Config{
		Host: "http://localhost:8081",
	})
	if err != nil {
		log.Fatal("Failed to initialize Flowable:", err)
	}
	app.flowable = flowableClient

	// Deploy BPMN Process
	_, err = app.flowable.Repository.Deployments.Create(&flowable.DeploymentCreate{
		Name: "Customer Onboarding Workflow",
		Files: map[string][]byte{
			"customer-onboarding.bpmn20.xml": []byte(bpmnXML), // Embed BPMN XML
		},
	})
	if err != nil {
		log.Printf("Warning: Failed to deploy BPMN: %v", err)
	}

	// Setup HTTP Server
	r := gin.Default()
	app.setupRoutes(r)

	app.httpServer = &http.Server{
		Addr:    ":8080",
		Handler: r,
	}

	// Start Kafka Consumer (simplified)
	go app.startKafkaConsumer()

	// Start Server
	go func() {
		if err := app.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal("Server failed:", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	app.shutdown()
}

func (app *App) setupRoutes(r *gin.Engine) {
	kafkaGroup := r.Group("/kafka")
	{
		kafkaGroup.POST("/caf", app.handleCAFRecord)
	}

	callbackGroup := r.Group("/callback")
	{
		callbackGroup.POST("/preact/:cafId", app.handlePreActivationCallback)
		callbackGroup.POST("/telver/:cafId", app.handleTeleVerificationCallback)
		callbackGroup.POST("/finalact/:cafId", app.handleFinalActivationCallback)
		callbackGroup.POST("/commission/:cafId", app.handleCommissionCallback)
	}

	r.GET("/status/:cafId", app.getCAFStatus)
}

func (app *App) handleCAFRecord(c *gin.Context) {
	var msg KafkaMessage
	if err := c.ShouldBindJSON(&msg); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	// Step 1: Save to CAF Table and Start Workflow
	cafID, err := app.saveCAFRecord(msg)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}

	// Start Flowable Process
	processInstance, err := app.flowable.Engine.ProcessInstances.Create(&flowable.StartProcessInstance{
		ProcessDefinitionKey: "customerOnboardingProcess",
		Variables: []flowable.Variable{
			{Name: "cafId", Value: strconv.Itoa(cafID)},
			{Name: "kafkaMessageId", Value: msg.ID},
		},
	})
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to start workflow"})
		return
	}

	c.JSON(200, gin.H{
		"message":    "CAF processed and workflow started",
		"caf_id":     cafID,
		"process_id": processInstance.ID,
	})
}

func (app *App) saveCAFRecord(msg KafkaMessage) (int, error) {
	// Determine Zone
	zoneCode, err := app.getZoneCode(msg.AgentHRNO)
	if err != nil {
		zoneCode = "NORTH" // Default
	}

	// Validate Plan Code and get IMSI
	imsi := msg.IMSI
	if app.isUSIMPlan(msg.PlanCode) {
		imsi = app.fetchPermanentIMSI(msg.IMSI) // PyIOTA API call simulation
	}

	var cafID int
	err = app.db.QueryRow(context.Background(),
		`INSERT INTO onboarding.caf (kafka_message_id, plan_code, imsi, permanent_imsi, pos_agent_hrno, csc_hrno, zone_code, customer_name, customer_phone, request_data, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'VALIDATED')
         RETURNING id`,
		msg.ID, msg.PlanCode, msg.IMSI, imsi, msg.AgentHRNO, msg.CSCHRNO, zoneCode,
		msg.Customer["name"], msg.Customer["phone"], msg.Customer).Scan(&cafID)

	return cafID, err
}

func (app *App) getZoneCode(hrno string) (string, error) {
	// Zone mapping logic - simplified
	zoneMap := map[string]string{
		"HR001": "NORTH",
		"HR002": "SOUTH",
		"HR003": "EAST",
		"HR004": "WEST",
	}
	if zone, exists := zoneMap[hrno]; exists {
		return zone, nil
	}
	return "NORTH", nil
}

func (app *App) isUSIMPlan(planCode string) bool {
	usimPlans := []string{"USIM001", "USIM002", "USIM003"}
	for _, plan := range usimPlans {
		if plan == planCode {
			return true
		}
	}
	return false
}

func (app *App) fetchPermanentIMSI(imsi string) string {
	// PyIOTA API simulation
	return "460001234567890" // Mock permanent IMSI
}

func (app *App) handlePreActivationCallback(c *gin.Context) {
	cafIDStr := c.Param("cafId")
	cafID, _ := strconv.Atoi(cafIDStr)

	var status struct {
		Status string                 `json:"status"`
		Data   map[string]interface{} `json:"data"`
	}
	c.ShouldBindJSON(&status)

	// Update status and signal Flowable task
	app.updateStatusAndSignal(cafID, "pre_activation", status.Status, status.Data)

	c.JSON(200, gin.H{"message": "Callback processed"})
}

// Similar handlers for other callbacks...
func (app *App) handleTeleVerificationCallback(c *gin.Context) {
	// Implementation similar to pre-activation
}

func (app *App) handleFinalActivationCallback(c *gin.Context) {
	// Implementation similar to pre-activation
}

func (app *App) handleCommissionCallback(c *gin.Context) {
	// Implementation similar to pre-activation
}

func (app *App) updateStatusAndSignal(cafID int, statusType, status string, data map[string]interface{}) {
	// Update respective status table
	// Signal Flowable task to continue
}

func (app *App) getCAFStatus(c *gin.Context) {
	cafIDStr := c.Param("cafId")
	cafID, _ := strconv.Atoi(cafIDStr)

	var caf struct {
		Status string `json:"status"`
	}
	err := app.db.QueryRow(context.Background(),
		"SELECT status FROM onboarding.caf WHERE id = $1", cafID).Scan(&caf.Status)

	if err != nil {
		c.JSON(404, gin.H{"error": "CAF not found"})
		return
	}

	c.JSON(200, caf)
}

func (app *App) startKafkaConsumer() {
	// Simplified Kafka consumer simulation
	for {
		time.Sleep(10 * time.Second)
		// Consume from Kafka topic "caf-topic"
		fmt.Println("Consuming Kafka messages...")
	}
}

func (app *App) shutdown() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	app.httpServer.Shutdown(ctx)
	app.db.Close()
	fmt.Println("Server gracefully shutdown")
}
