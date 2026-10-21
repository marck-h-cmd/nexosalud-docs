-- ====================================================================================================
-- CONEXIÓN 1: EJECUCIÓN CON RETENCIÓN CONTROLADA DE BLOQUEO (H3 - LEAD)
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Conc;
GO

PRINT '>> Conexión 1 [SPID ' + CAST(@@SPID AS VARCHAR(10)) + ']: Abriendo transacción externa...';
BEGIN TRANSACTION;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead 
    @FechaCorte = '2026-09-30', 
    @ConfigHitoConversion = 'CreacionReserva',
    @BatchId = 'BATCH_CONC_LEAD_1',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Conc',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT;

PRINT '>> Conexión 1: Carga completada. Reteniendo bloqueo exclusivo en transacción externa (@@TRANCOUNT = ' + CAST(@@TRANCOUNT AS VARCHAR(5)) + ')...';
WAITFOR DELAY '00:00:06';

COMMIT TRANSACTION;
PRINT '>> Conexión 1: Transacción externa confirmada y bloqueo liberado exitosamente.';
PRINT '>> Conexión 1 Resultados: Insertados = ' + CAST(@Ins AS VARCHAR(10)) + ', Actualizados = ' + CAST(@Act AS VARCHAR(10)) + ', SinCambio = ' + CAST(@Sin AS VARCHAR(10)) + ', Rechazados = ' + CAST(@Rec AS VARCHAR(10));
GO
