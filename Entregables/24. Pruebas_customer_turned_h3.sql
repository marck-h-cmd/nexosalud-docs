-- Bateria sintetica. Ejecutar solo en el mart aislado creado por ejecutar_pruebas_alexis.ps1.
SET NOCOUNT ON;
DECLARE @I INT,@A INT,@S INT,@R INT,@P INT;
EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2026-11-01','ALEXIS-T01',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>6 OR @A<>0 OR @S<>0 OR @R<>2 OR @P<>1 THROW 51201,'T01 CUSTOMER carga inicial incorrecta.',1;
IF (SELECT COUNT(*) FROM dbo.Fact_AtencionCustomer)<>6 THROW 51202,'T01 cardinalidad CUSTOMER incorrecta.',1;
IF (SELECT SUM(CitasEvaluables) FROM dbo.Fact_AtencionCustomer)<>3 THROW 51203,'T01 denominador C1/C2 incorrecto.',1;
IF (SELECT SUM(AtencionesRealizadas) FROM dbo.Fact_AtencionCustomer)<>2 THROW 51204,'T01 C1 incorrecto.',1;
IF (SELECT SUM(CitasConInasistencia) FROM dbo.Fact_AtencionCustomer)<>1 THROW 51205,'T01 no-show explicito sin Atenciones perdido.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_AtencionCustomer WHERE id_reserva_origen=3 AND id_atencion_origen IS NULL AND ResultadoCita='NoShow')
 THROW 51206,'T01 reserva sin Atenciones no quedo en fact.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_AtencionCustomer WHERE id_reserva_origen=4 AND ResultadoCita='PendienteResultado' AND CitasEvaluables=0)
 THROW 51207,'T01 pendiente inferido como no-show.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_AtencionCustomer WHERE id_reserva_origen=5 AND ResultadoCita='Futura')
 THROW 51208,'T01 cita futura evaluada.',1;
IF (SELECT SUM(AtencionesFinalizadasConformes) FROM dbo.Fact_AtencionCustomer)<>2 THROW 51209,'T01 C4 incorrecto.',1;
IF (SELECT SUM(COALESCE(TiempoEnSillonDentalMin,0)) FROM dbo.Fact_AtencionCustomer)<>80 THROW 51227,'T01 C3 minutos incorrectos.',1;
IF (SELECT COUNT(*) FROM dbo.Rechazos_ETL_Customer WHERE BatchId='ALEXIS-T01')<>2
 THROW 51210,'T01 rechazos CUSTOMER incorrectos.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Rechazos_ETL_Customer WHERE BatchId='ALEXIS-T01' AND MotivoRechazo='DuracionNegativa')
 OR NOT EXISTS(SELECT 1 FROM dbo.Rechazos_ETL_Customer WHERE BatchId='ALEXIS-T01' AND MotivoRechazo='MultiplesAtencionesPorReserva')
 THROW 51228,'T01 causas de rechazo incorrectas.',1;
PRINT 'T01 CUSTOMER carga, grano, C1/C2/C4, futuro, pendiente y rechazos: CORRECTO';

EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2026-11-01','ALEXIS-T02',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>0 OR @S<>6 OR @R<>2 OR (SELECT COUNT(*) FROM dbo.Fact_AtencionCustomer)<>6
 THROW 51211,'T02 CUSTOMER no idempotente.',1;
PRINT 'T02 CUSTOMER rerun idempotente: CORRECTO';

EXEC dbo.usp_Cargar_Fact_SeguimientoTurned '2026-11-01','ALEXIS-T03',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>1 OR @A<>0 OR @R<>2 OR @P<>1 THROW 51212,'T03 TURNED carga incorrecta.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_SeguimientoTurned WHERE id_seguimiento_origen=1 AND Cohorte90DiasEvaluable=0 AND Retorno90Dias=0)
 THROW 51213,'T03 cohorte inmadura se conto como retorno.',1;
PRINT 'T03 TURNED seguimiento, huerfano, identidad y cohorte inmadura: CORRECTO';

EXEC dbo.usp_Cargar_Fact_SeguimientoTurned '2026-11-01','ALEXIS-T04',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>0 OR @S<>1 OR (SELECT COUNT(*) FROM dbo.Fact_SeguimientoTurned)<>1
 THROW 51214,'T04 TURNED no idempotente.',1;
PRINT 'T04 TURNED rerun idempotente: CORRECTO';

EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2027-02-01','ALEXIS-T05',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>1 OR @S<>5 OR @P<>2 THROW 51215,'T05 cambio futuro a pendiente incorrecto.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_AtencionCustomer WHERE id_reserva_origen=5 AND ResultadoCita='PendienteResultado')
 THROW 51216,'T05 no se actualizo cita vencida.',1;
PRINT 'T05 CUSTOMER cambio de corte temporal: CORRECTO';

EXEC dbo.usp_Cargar_Fact_SeguimientoTurned '2027-02-01','ALEXIS-T06',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>1 OR @S<>0 OR @P<>0 THROW 51217,'T06 madurez TURNED incorrecta.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_SeguimientoTurned WHERE id_seguimiento_origen=1 AND Cohorte90DiasEvaluable=1 AND Retorno90Dias=1)
 THROW 51218,'T06 retorno posterior no detectado.',1;
PRINT 'T06 TURNED madurez de 90 dias y retorno: CORRECTO';

UPDATE [$(OLTP_DB)].dbo.Reservas SET estado='No-Show' WHERE id_reserva=4;
EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2027-02-01','ALEXIS-T07',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>1 OR (SELECT SUM(CitasConInasistencia) FROM dbo.Fact_AtencionCustomer)<>2
 THROW 51219,'T07 actualizacion de resultado incorrecta.',1;
PRINT 'T07 CUSTOMER cambio de estado y actualizacion in-place: CORRECTO';

UPDATE [$(OLTP_DB)].dbo.Atenciones SET indicaciones_finales='x' WHERE id_atencion=1;
EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2027-02-01','ALEXIS-T08',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>1 OR (SELECT SUM(AtencionesFinalizadasConformes) FROM dbo.Fact_AtencionCustomer)<>1
 THROW 51220,'T08 auditoria C4 incorrecta.',1;
IF EXISTS(SELECT id_reserva_origen FROM dbo.Fact_AtencionCustomer GROUP BY id_reserva_origen HAVING COUNT(*)>1)
 THROW 51221,'T08 duplicados de reserva.',1;
PRINT 'T08 C4 actualizable y unicidad: CORRECTO';

UPDATE [$(OLTP_DB)].dbo.Atenciones SET fecha_fin='2026-10-01 08:00' WHERE id_atencion=1;
EXEC dbo.usp_Cargar_Fact_AtencionCustomer '2027-02-01','ALEXIS-T09',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @I<>0 OR @A<>1 OR @R<>3
 THROW 51222,'T09 invalidacion CUSTOMER incorrecta.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.Fact_AtencionCustomer WHERE id_reserva_origen=1
 AND ResultadoCita='Rechazada' AND CitasProgramadas=0 AND CitasEvaluables=0)
 THROW 51223,'T09 fila anterior sigue contaminando KPI.',1;
PRINT 'T09 CUSTOMER fuente invalidada neutralizada en el hecho: CORRECTO';

UPDATE [$(OLTP_DB)].dbo.Seguimientos SET id_persona=2 WHERE id_seguimiento=1;
EXEC dbo.usp_Cargar_Fact_SeguimientoTurned '2027-02-01','ALEXIS-T10',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @A<>1 OR @R<>3 OR (SELECT SeguimientosRegistrados FROM dbo.Fact_SeguimientoTurned WHERE id_seguimiento_origen=1)<>0
 THROW 51224,'T10 invalidacion TURNED incorrecta.',1;
PRINT 'T10 TURNED fuente invalidada neutralizada: CORRECTO';

UPDATE [$(OLTP_DB)].dbo.Seguimientos SET id_persona=1 WHERE id_seguimiento=1;
EXEC dbo.usp_Cargar_Fact_SeguimientoTurned '2027-02-01','ALEXIS-T11',@I OUTPUT,@A OUTPUT,@S OUTPUT,@R OUTPUT,@P OUTPUT;
IF @A<>1 OR @R<>2 OR (SELECT SeguimientosRegistrados FROM dbo.Fact_SeguimientoTurned WHERE id_seguimiento_origen=1)<>1
 THROW 51225,'T11 reactivacion TURNED incorrecta.',1;
PRINT 'T11 TURNED fuente corregida reactivada: CORRECTO';

IF (SELECT COUNT(*) FROM dbo.Log_Ejecucion_ETL WHERE TipoEvento='EXITO')<>11
 THROW 51226,'T12 bitacora incompleta.',1;
PRINT 'T12 auditoria de once cargas: CORRECTO';
PRINT 'RESULTADO: 12/12 CASOS SQL CORRECTOS';
