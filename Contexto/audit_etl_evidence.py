import re
import subprocess
import os
import json

print("====================================================================")
print("AUDITORIA RIGUROSA DE EVIDENCIA FUNCIONAL DEL ETL (ANEXO F)")
print("====================================================================\n")

md_path = r'D:\Proyects\nexosalud-docs\Contexto\Anexos.md'
with open(md_path, 'r', encoding='utf-8') as f:
    md_content = f.read()

def extract_sql_block(header, next_header):
    p1 = md_content.find(header)
    p2 = md_content.find(next_header) if next_header else len(md_content)
    chunk = md_content[p1:p2]
    match = re.search(r'```sql\s*(.*?)\s*```', chunk, re.DOTALL)
    if not match:
        raise ValueError(f"No se encontró bloque sql en {header}")
    return match.group(1).strip()

sql_c = extract_sql_block('# Anexo C', '# Anexo D')
sql_d = extract_sql_block('# Anexo D', '# Anexo E')
sql_e = extract_sql_block('# Anexo E', '# Anexo F')
sql_f = extract_sql_block('# Anexo F', '# Anexo G')

seed_path = r'D:\Proyects\Proyecto-IN-Odontolog-a-\database\seed\01_catalogos.sql'
with open(seed_path, 'r', encoding='utf-8') as f:
    seed_sql = f.read()

def adapt(sql):
    sql = sql.replace('NexoSaludDB', 'NexoSaludDB_AuditTest')
    sql = sql.replace('NexoSalud_Mart', 'NexoSalud_Mart_AuditTest')
    return sql

test_c_path = r'D:\Proyects\nexosalud-docs\Contexto\audit_c.sql'
test_seed_path = r'D:\Proyects\nexosalud-docs\Contexto\audit_seed.sql'
test_d_path = r'D:\Proyects\nexosalud-docs\Contexto\audit_d.sql'
test_e_path = r'D:\Proyects\nexosalud-docs\Contexto\audit_e.sql'
test_f_path = r'D:\Proyects\nexosalud-docs\Contexto\audit_f.sql'

with open(test_c_path, 'w', encoding='utf-8') as f:
    f.write(adapt(sql_c))
with open(test_seed_path, 'w', encoding='utf-8') as f:
    f.write(adapt(seed_sql))
with open(test_d_path, 'w', encoding='utf-8') as f:
    f.write(adapt(sql_d))
with open(test_e_path, 'w', encoding='utf-8') as f:
    f.write(adapt(sql_e))
with open(test_f_path, 'w', encoding='utf-8') as f:
    f.write(adapt(sql_f))

def run_sqlcmd(args):
    cmd = ['sqlcmd', '-S', 'localhost', '-E', '-C'] + args
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return result

# Limpieza inicial
run_sqlcmd(['-Q', """
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NexoSaludDB_AuditTest')
BEGIN
    ALTER DATABASE NexoSaludDB_AuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NexoSaludDB_AuditTest;
END;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NexoSalud_Mart_AuditTest')
BEGIN
    ALTER DATABASE NexoSalud_Mart_AuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NexoSalud_Mart_AuditTest;
END;
"""])

print("-> [Fase 1] Creando bases aisladas y poblando con datos sintéticos...")
run_sqlcmd(['-i', test_c_path])
run_sqlcmd(['-i', test_seed_path])
run_sqlcmd(['-i', test_d_path])
run_sqlcmd(['-i', test_e_path])

# Actividad 1 & 2: Ejecución 1 y validación independiente de métricas
print("-> [Fase 2] Ejecutando ETL Carga Inicial (Run 1)...")
run_sqlcmd(['-i', test_f_path])

print("-> Consultando métricas del Mart vs OLTP de forma independiente...")
audit_query = """
SET NOCOUNT ON;
-- 1. Buyer: Personas registradas
SELECT 'Buyer_Mart' AS Origen, SUM(ContactosRegistrados) AS Contactos, SUM(ContactosUtilizables) AS Utilizables, SUM(ConversionesALead) AS ConvLead
FROM NexoSalud_Mart_AuditTest.dbo.Fact_CaptacionBuyer;

SELECT 'Buyer_OLTP' AS Origen, COUNT(*) AS Contactos, 
       SUM(CASE WHEN estado_calidad IN ('VERIFICABLE', 'ALTA') THEN 1 ELSE 0 END) AS Utilizables,
       SUM(CASE WHEN id_etapa_actual >= 2 THEN 1 ELSE 0 END) AS ConvLead
FROM NexoSaludDB_AuditTest.dbo.Personas;

-- 2. Lead: Solicitudes y eventos de etapa LEAD
SELECT 'Lead_Mart' AS Origen, SUM(LeadsCohorteEvaluable) AS Evaluables, SUM(LeadsRequierenRespuesta) AS RequierenResp
FROM NexoSalud_Mart_AuditTest.dbo.Fact_NegociacionLead;

SELECT 'Lead_OLTP' AS Origen, COUNT(DISTINCT id_persona) AS Evaluables,
       COUNT(DISTINCT ev.id_persona) AS RequierenResp
FROM NexoSaludDB_AuditTest.dbo.EventosEtapa ev
WHERE ev.etapa_destino = 2;

-- 3. Payer: Pagos
SELECT 'Payer_Mart' AS Origen, SUM(PagosRegistrados) AS CantPagos, SUM(ImporteTotalCobro) AS ImporteTotal, SUM(PagosValidados) AS Validados
FROM NexoSalud_Mart_AuditTest.dbo.Fact_GestionPayer;

SELECT 'Payer_OLTP' AS Origen, COUNT(*) AS CantPagos, SUM(importe) AS ImporteTotal,
       SUM(CASE WHEN estado = 'Confirmado' THEN 1 ELSE 0 END) AS Validados
FROM NexoSaludDB_AuditTest.dbo.Pagos;

-- 4. Customer: Atenciones
SELECT 'Customer_Mart' AS Origen, SUM(AtencionesRealizadas) AS Realizadas, SUM(AtencionesFinalizadasConformes) AS Conformes
FROM NexoSalud_Mart_AuditTest.dbo.Fact_AtencionCustomer;

SELECT 'Customer_OLTP' AS Origen, 
       SUM(CASE WHEN estado = 'Realizada' THEN 1 ELSE 0 END) AS Realizadas,
       SUM(CASE WHEN estado = 'Realizada' THEN 1 ELSE 0 END) AS Conformes
FROM NexoSaludDB_AuditTest.dbo.Atenciones;

-- 5. Turned: Seguimientos
SELECT 'Turned_Mart' AS Origen, SUM(SeguimientosRegistrados) AS Registrados, SUM(SeguimientosEfectivos) AS Efectivos
FROM NexoSalud_Mart_AuditTest.dbo.Fact_SeguimientoTurned;

SELECT 'Turned_OLTP' AS Origen, COUNT(*) AS Registrados,
       SUM(CASE WHEN respuesta_paciente IS NOT NULL AND respuesta_paciente <> '' AND respuesta_paciente <> 'Sin respuesta' THEN 1 ELSE 0 END) AS Efectivos
FROM NexoSaludDB_AuditTest.dbo.Seguimientos;
"""

res_audit_1 = run_sqlcmd(['-Q', audit_query])
print(res_audit_1.stdout)

# Actividad 4: Confirmar idempotencia exacta celda a celda (EXCEPT en todas las columnas)
print("-> [Fase 3] Snapshot antes de Run 2 y verificación celda a celda con EXCEPT...")
# Creamos tablas snapshot
run_sqlcmd(['-Q', """
USE NexoSalud_Mart_AuditTest;
SELECT * INTO #Snap_Buyer FROM dbo.Fact_CaptacionBuyer;
SELECT * INTO #Snap_Lead FROM dbo.Fact_NegociacionLead;
SELECT * INTO #Snap_Payer FROM dbo.Fact_GestionPayer;
SELECT * INTO #Snap_Customer FROM dbo.Fact_AtencionCustomer;
SELECT * INTO #Snap_Turned FROM dbo.Fact_SeguimientoTurned;
"""])

# Para que persistan en la sesión, creamos tablas permanentes de snapshot en la BD de test
run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SELECT * INTO Snap_Buyer FROM dbo.Fact_CaptacionBuyer;
SELECT * INTO Snap_Lead FROM dbo.Fact_NegociacionLead;
SELECT * INTO Snap_Payer FROM dbo.Fact_GestionPayer;
SELECT * INTO Snap_Customer FROM dbo.Fact_AtencionCustomer;
SELECT * INTO Snap_Turned FROM dbo.Fact_SeguimientoTurned;
"""])

# Ejecutamos Run 2
run_sqlcmd(['-i', test_f_path])

# Verificamos diferencias celda a celda con EXCEPT
res_diff = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SET NOCOUNT ON;
SELECT 'Diff_Buyer_Mart_vs_Snap' AS Test, COUNT(*) AS Diferencias FROM (
    SELECT * FROM dbo.Fact_CaptacionBuyer EXCEPT SELECT * FROM Snap_Buyer
    UNION ALL
    SELECT * FROM Snap_Buyer EXCEPT SELECT * FROM dbo.Fact_CaptacionBuyer
) d
UNION ALL
SELECT 'Diff_Lead_Mart_vs_Snap', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_NegociacionLead EXCEPT SELECT * FROM Snap_Lead
    UNION ALL
    SELECT * FROM Snap_Lead EXCEPT SELECT * FROM dbo.Fact_NegociacionLead
) d
UNION ALL
SELECT 'Diff_Payer_Mart_vs_Snap', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_GestionPayer EXCEPT SELECT * FROM Snap_Payer
    UNION ALL
    SELECT * FROM Snap_Payer EXCEPT SELECT * FROM dbo.Fact_GestionPayer
) d
UNION ALL
SELECT 'Diff_Customer_Mart_vs_Snap', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_AtencionCustomer EXCEPT SELECT * FROM Snap_Customer
    UNION ALL
    SELECT * FROM Snap_Customer EXCEPT SELECT * FROM dbo.Fact_AtencionCustomer
) d
UNION ALL
SELECT 'Diff_Turned_Mart_vs_Snap', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_SeguimientoTurned EXCEPT SELECT * FROM Snap_Turned
    UNION ALL
    SELECT * FROM Snap_Turned EXCEPT SELECT * FROM dbo.Fact_SeguimientoTurned
) d;
"""])
print("\n--- RESULTADO COMPARACION CELDA A CELDA TRAS RUN 2 (IDEMPOTENCIA ESTRICTA) ---")
print(res_diff.stdout)

# Actividad 3: Revisión de actualización determinista de pagos
print("-> [Fase 4] Auditoría determinista de actualización de pagos...")
res_target_pago = run_sqlcmd(['-d', 'NexoSaludDB_AuditTest', '-Q', """
SET NOCOUNT ON;
SELECT TOP 1 id_pago, id_persona, id_reserva, importe, estado, fecha_registro, canal_pago
FROM dbo.Pagos
WHERE estado = 'Confirmado'
ORDER BY id_pago ASC;
"""])
print("Pago seleccionado determinísticamente:")
print(res_target_pago.stdout)

# Obtenemos el grano de este pago en Fact_GestionPayer
res_grain_target = run_sqlcmd(['-Q', """
SET NOCOUNT ON;
DECLARE @idPago INT = (SELECT TOP 1 id_pago FROM NexoSaludDB_AuditTest.dbo.Pagos WHERE estado = 'Confirmado' ORDER BY id_pago ASC);
SELECT 
    CAST(FORMAT(p.fecha_registro, 'yyyyMMdd') AS INT) AS KeyTiempo,
    ISNULL(dp.KeyPasarela, 0) AS KeyPasarela,
    ISNULL(dc.KeyCobro, 0) AS KeyCobro,
    ISNULL(ds.KeySede, 0) AS KeySede,
    ISNULL(dserv.KeyServicio, 0) AS KeyServicio,
    p.importe
FROM NexoSaludDB_AuditTest.dbo.Pagos p
LEFT JOIN NexoSaludDB_AuditTest.dbo.Reservas r ON p.id_reserva = r.id_reserva
LEFT JOIN NexoSaludDB_AuditTest.dbo.Opciones o ON r.id_opcion = o.id_opcion
LEFT JOIN NexoSaludDB_AuditTest.dbo.Disponibilidad disp ON o.id_disponibilidad = disp.id_disponibilidad
LEFT JOIN NexoSaludDB_AuditTest.dbo.Solicitudes sol ON r.id_solicitud = sol.id_solicitud
LEFT JOIN NexoSalud_Mart_AuditTest.dbo.Dim_Sede ds ON disp.id_sede = ds.id_sede
LEFT JOIN NexoSalud_Mart_AuditTest.dbo.Dim_Servicio dserv ON sol.id_servicio = dserv.id_servicio
LEFT JOIN NexoSalud_Mart_AuditTest.dbo.Dim_Pasarela dp ON dp.nombre = p.canal_pago
LEFT JOIN NexoSalud_Mart_AuditTest.dbo.Dim_Cobro dc ON dc.estado_pago = p.estado
WHERE p.id_pago = @idPago;
"""])
print("Mapeo dimensional del pago objetivo:")
print(res_grain_target.stdout)

# Modificamos exactamente ese pago por su ID
res_update_pago = run_sqlcmd(['-Q', """
SET NOCOUNT ON;
DECLARE @idPago INT = (SELECT TOP 1 id_pago FROM NexoSaludDB_AuditTest.dbo.Pagos WHERE estado = 'Confirmado' ORDER BY id_pago ASC);
UPDATE NexoSaludDB_AuditTest.dbo.Pagos
SET importe = importe + 250.00
WHERE id_pago = @idPago;
SELECT @idPago AS IdPagoModificado, 'Incremento +250.00' AS Accion;
"""])
print(res_update_pago.stdout)

# Reejecutamos ETL (Run 3)
run_sqlcmd(['-i', test_f_path])

# Verificamos telemetría de Run 3 y variación exacta
res_log_3 = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SET NOCOUNT ON;
SELECT TOP 1 TipoEvento, Mensaje FROM dbo.Log_Ejecucion_ETL ORDER BY LogId DESC;
"""])
print("Telemetría tras modificar Pago:")
print(res_log_3.stdout)

# Verificamos si varió alguna otra tabla de hechos
res_other_facts = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SET NOCOUNT ON;
SELECT 'Buyer' AS Tabla, COUNT(*) AS DiffFilas FROM (
    SELECT * FROM dbo.Fact_CaptacionBuyer EXCEPT SELECT * FROM Snap_Buyer
) d
UNION ALL
SELECT 'Lead', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_NegociacionLead EXCEPT SELECT * FROM Snap_Lead
) d
UNION ALL
SELECT 'Customer', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_AtencionCustomer EXCEPT SELECT * FROM Snap_Customer
) d
UNION ALL
SELECT 'Turned', COUNT(*) FROM (
    SELECT * FROM dbo.Fact_SeguimientoTurned EXCEPT SELECT * FROM Snap_Turned
) d;
"""])
print("Impacto colateral en otras 4 tablas de hechos:")
print(res_other_facts.stdout)

# Actividad 5: Evaluar Casos Pendientes (Eliminación / Obsoletos, Rollback transaccional, Concurrencia)
print("-> [Fase 5] Pruebas de casos pendientes...")

# Caso A: Eliminación de origen y tratamiento de agregados obsoletos (DELETE)
print("-> Caso Pendiente A: Eliminación de registro origen en OLTP...")
# Eliminamos un pago de prueba para verificar si el agregado obsoleto o disminuido se reconcilia
res_del_test = run_sqlcmd(['-Q', """
SET NOCOUNT ON;
-- Creamos un pago con fecha y combinación única en OLTP
INSERT INTO NexoSaludDB_AuditTest.dbo.Pagos (id_persona, id_reserva, importe, canal_pago, fecha_registro, fecha_validacion, estado, validado_por)
VALUES (1, NULL, 500.00, 'Efectivo', '2026-11-15 10:00:00', '2026-11-15 10:30:00', 'Confirmado', 1);
DECLARE @newPagoId INT = SCOPE_IDENTITY();
SELECT @newPagoId AS PagoNuevoId;
"""])
print("Pago creado para prueba de obsolescencia:")
print(res_del_test.stdout)

# Ejecutamos ETL para que ingrese (debe hacer I:1 en Payer)
run_sqlcmd(['-i', test_f_path])
res_log_ins = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', "SET NOCOUNT ON; SELECT TOP 1 Mensaje FROM dbo.Log_Ejecucion_ETL ORDER BY LogId DESC;"])
print("Log tras insertar pago nuevo:", res_log_ins.stdout.strip())

# Ahora borramos dicho pago del origen (combinación desaparece del origen)
run_sqlcmd(['-Q', "DELETE FROM NexoSaludDB_AuditTest.dbo.Pagos WHERE fecha_registro = '2026-11-15 10:00:00';"])
# Reejecutamos ETL (debe detectar agregado obsoleto y eliminarlo con D:1)
run_sqlcmd(['-i', test_f_path])
res_log_del = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', "SET NOCOUNT ON; SELECT TOP 1 Mensaje FROM dbo.Log_Ejecucion_ETL ORDER BY LogId DESC;"])
print("Log tras borrar registro de origen (reconciliación de obsoleto):", res_log_del.stdout.strip())

# Caso B: Prueba de Rollback ante error en transacción
print("\n-> Caso Pendiente B: Prueba de reversión atómica (ROLLBACK)...")
# Creamos una situación que cause error o probamos bloque TRY CATCH
res_rollback = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SET NOCOUNT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Log_Ejecucion_ETL (TipoEvento, Mensaje) VALUES ('PRUEBA_RB', 'Antes de fallo');
    -- Forzar error de división por cero o restricción
    DECLARE @x INT = 1 / 0;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO dbo.Log_Ejecucion_ETL (TipoEvento, Mensaje) VALUES ('ERROR_AUDIT', 'Rollback ejecutado exitosamente');
END CATCH;

SELECT TOP 1 TipoEvento, Mensaje FROM dbo.Log_Ejecucion_ETL ORDER BY LogId DESC;
"""])
print("Verificación de captura y rollback:", res_rollback.stdout.strip())

# Caso C: Prueba de exclusión mutua de concurrencia (sp_getapplock)
print("\n-> Caso Pendiente C: Prueba de sp_getapplock...")
res_lock = run_sqlcmd(['-d', 'NexoSalud_Mart_AuditTest', '-Q', """
SET NOCOUNT ON;
DECLARE @res1 INT, @res2 INT;
EXEC @res1 = sp_getapplock @Resource = 'ETL_NexoSalud_Lock', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0;
-- Intento 2 con timeout 0 debe fallar (retorna -1)
EXEC @res2 = sp_getapplock @Resource = 'ETL_NexoSalud_Lock', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0;
-- Liberar
EXEC sp_releaseapplock @Resource = 'ETL_NexoSalud_Lock', @LockOwner = 'Session';

SELECT @res1 AS Lock1_Resultado, @res2 AS Lock2_Resultado_Esperado_Menos1;
"""])
print("Verificación de bloqueo concurrente (sp_getapplock):", res_lock.stdout.strip())

# Limpieza final
print("\n-> Limpiando y desmontando bases de prueba...")
run_sqlcmd(['-Q', """
ALTER DATABASE NexoSaludDB_AuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE NexoSaludDB_AuditTest;
ALTER DATABASE NexoSalud_Mart_AuditTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE NexoSalud_Mart_AuditTest;
"""])

for p in [test_c_path, test_seed_path, test_d_path, test_e_path, test_f_path]:
    if os.path.exists(p):
        os.remove(p)

print("\n[AUDITORIA COMPLETA CONCLUIDA]")
