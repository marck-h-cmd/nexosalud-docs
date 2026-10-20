-- ====================================================================
-- NEXOSALUD — SUITE DE PRUEBAS Y VALIDACIÓN DEL POBLAMIENTO
-- Integrante 2: Marck Alessandro Hermenegildo Pacheco
-- Bases de Datos: NexoSaludDB y NexoSalud_Mart
-- ====================================================================

USE NexoSalud_Mart;
GO

PRINT '==============================================================';
PRINT 'PRUEBA 1: CONTEO DE FILAS EN TODAS LAS TABLAS DEL DATA MART';
PRINT '==============================================================';

SELECT 'Dim_Tiempo' AS Tabla, COUNT(*) AS TotalFilas FROM dbo.Dim_Tiempo
UNION ALL
SELECT 'Dim_Hora', COUNT(*) FROM dbo.Dim_Hora
UNION ALL
SELECT 'Dim_Sede', COUNT(*) FROM dbo.Dim_Sede
UNION ALL
SELECT 'Dim_Servicio', COUNT(*) FROM dbo.Dim_Servicio
UNION ALL
SELECT 'Dim_Canal', COUNT(*) FROM dbo.Dim_Canal
UNION ALL
SELECT 'Dim_Fuente', COUNT(*) FROM dbo.Dim_Fuente
UNION ALL
SELECT 'Dim_Campana', COUNT(*) FROM dbo.Dim_Campana
UNION ALL
SELECT 'Dim_TipoPersona', COUNT(*) FROM dbo.Dim_TipoPersona
UNION ALL
SELECT 'Dim_Pagador', COUNT(*) FROM dbo.Dim_Pagador
UNION ALL
SELECT 'Dim_Profesional', COUNT(*) FROM dbo.Dim_Profesional
UNION ALL
SELECT 'Dim_Negociador', COUNT(*) FROM dbo.Dim_Negociador
UNION ALL
SELECT 'Dim_Pasarela', COUNT(*) FROM dbo.Dim_Pasarela
UNION ALL
SELECT 'Dim_Cobro', COUNT(*) FROM dbo.Dim_Cobro
UNION ALL
SELECT 'Dim_EstadoAtencion', COUNT(*) FROM dbo.Dim_EstadoAtencion
UNION ALL
SELECT 'Dim_EstadoRegistro', COUNT(*) FROM dbo.Dim_EstadoRegistro
UNION ALL
SELECT 'Fact_CaptacionBuyer', COUNT(*) FROM dbo.Fact_CaptacionBuyer
UNION ALL
SELECT 'Fact_NegociacionLead', COUNT(*) FROM dbo.Fact_NegociacionLead
UNION ALL
SELECT 'Fact_GestionPayer', COUNT(*) FROM dbo.Fact_GestionPayer
UNION ALL
SELECT 'Fact_AtencionCustomer', COUNT(*) FROM dbo.Fact_AtencionCustomer;
GO

PRINT '==============================================================';
PRINT 'PRUEBA 2: CONCILIACIÓN DE MÉTRICAS CLAVE (OLTP vs DATA MART)';
PRINT '==============================================================';

-- 2.1 Conciliación de Pagos Validados
SELECT 
    'NexoSaludDB (OLTP)' AS Origen,
    COUNT(*) AS TotalPagosValidados,
    SUM(importe) AS MontoTotalRecaudado
FROM NexoSaludDB.dbo.Pagos
WHERE UPPER(estado) = 'VALIDATED'
UNION ALL
SELECT 
    'NexoSalud_Mart (Data Mart)',
    SUM(PagosValidados),
    SUM(ImporteTotalCobro)
FROM NexoSalud_Mart.dbo.Fact_GestionPayer;

-- 2.2 Conciliación de Atenciones Asistidas vs No-Show
SELECT 
    'NexoSaludDB (OLTP)' AS Origen,
    SUM(CASE WHEN asistencia = 'Asistió' THEN 1 ELSE 0 END) AS AtencionesAsistidas,
    SUM(CASE WHEN asistencia = 'No asistió' THEN 1 ELSE 0 END) AS InasistenciasNoShow
FROM NexoSaludDB.dbo.Atenciones
UNION ALL
SELECT 
    'NexoSalud_Mart (Data Mart)',
    SUM(AtencionesRealizadas),
    SUM(CitasConInasistencia)
FROM NexoSalud_Mart.dbo.Fact_AtencionCustomer;
GO

PRINT '==============================================================';
PRINT 'PRUEBA 3: MUESTRA ANALÍTICA CON JOINS A DIMENSIONES';
PRINT '==============================================================';

-- 3.1 Consulta de Recaudación por Sede y Método de Cobro
SELECT 
    ds.Sede,
    dp.MetodoPago,
    dc.EstadoPago,
    SUM(f.PagosRegistrados) AS TotalPagos,
    SUM(f.ImporteTotalCobro) AS TotalRecaudado
FROM dbo.Fact_GestionPayer f
INNER JOIN dbo.Dim_Sede ds ON f.KeySede = ds.KeySede
INNER JOIN dbo.Dim_Pasarela dp ON f.KeyPasarela = dp.KeyPasarela
INNER JOIN dbo.Dim_Cobro dc ON f.KeyCobro = dc.KeyCobro
GROUP BY ds.Sede, dp.MetodoPago, dc.EstadoPago
ORDER BY TotalRecaudado DESC;

-- 3.2 Consulta de Atenciones por Odontólogo y Servicio
SELECT 
    dprof.Odontologo,
    dserv.ServicioOdontologico,
    SUM(f.CitasEvaluables) AS CitasProgramadas,
    SUM(f.AtencionesRealizadas) AS AtencionesEfectivas,
    SUM(f.CitasConInasistencia) AS NoShows
FROM dbo.Fact_AtencionCustomer f
INNER JOIN dbo.Dim_Profesional dprof ON f.KeyProfesional = dprof.KeyProfesional
INNER JOIN dbo.Dim_Servicio dserv ON f.KeyServicio = dserv.KeyServicio
GROUP BY dprof.Odontologo, dserv.ServicioOdontologico
ORDER BY AtencionesEfectivas DESC;
GO
