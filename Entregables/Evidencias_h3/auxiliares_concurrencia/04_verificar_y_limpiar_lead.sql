-- ====================================================================================================
-- VERIFICACIÓN FINAL Y LIMPIEZA: PRUEBA DE CONCURRENCIA LEAD (H3)
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Conc;
GO

SELECT 
    COUNT(*) AS TotalFilasHechos,
    COUNT(DISTINCT id_solicitud_origen) AS TotalSolicitudesUnicas,
    SUM(CASE WHEN SolicitudesRegistradas = 1 THEN 1 ELSE 0 END) AS TotalMetricaSolicitudes
FROM dbo.Fact_NegociacionLead;
GO

SELECT 
    LogId, Procedimiento, BatchId, TipoEvento, Mensaje
FROM dbo.Log_Ejecucion_ETL
ORDER BY LogId;
GO

USE master;
GO

IF DB_ID('Test_NexoSalud_Mart_Lead_Conc') IS NOT NULL
    DROP DATABASE [Test_NexoSalud_Mart_Lead_Conc];
GO

IF DB_ID('Test_NexoSalud_OLTP_Lead_Conc') IS NOT NULL
    DROP DATABASE [Test_NexoSalud_OLTP_Lead_Conc];
GO

PRINT '>> Limpieza de bases de concurrencia completada.';
GO
