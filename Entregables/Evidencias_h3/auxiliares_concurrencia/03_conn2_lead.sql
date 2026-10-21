-- ====================================================================================================
-- CONEXIÓN 2: EJECUCIÓN CONCURRENTE CON ESPERA OBSERVADA (H3 - LEAD)
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Conc;
GO

PRINT '>> Conexión 2 [SPID ' + CAST(@@SPID AS VARCHAR(10)) + ']: Invocando dbo.usp_Cargar_Fact_NegociacionLead concurrentemente...';
DECLARE @tInicio DATETIME2 = SYSDATETIME();
DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT;

EXEC dbo.usp_Cargar_Fact_NegociacionLead 
    @FechaCorte = '2026-09-30', 
    @ConfigHitoConversion = 'CreacionReserva',
    @BatchId = 'BATCH_CONC_LEAD_2',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Conc',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT;

DECLARE @tFin DATETIME2 = SYSDATETIME();
PRINT '>> Conexión 2: Finalizada tras adquirir el bloqueo en ' + CAST(DATEDIFF(millisecond, @tInicio, @tFin) AS VARCHAR(10)) + ' ms.';
PRINT '>> Conexión 2 Resultados: Insertados = ' + CAST(@Ins AS VARCHAR(10)) + ', Actualizados = ' + CAST(@Act AS VARCHAR(10)) + ', SinCambio = ' + CAST(@Sin AS VARCHAR(10)) + ', Rechazados = ' + CAST(@Rec AS VARCHAR(10));
GO
