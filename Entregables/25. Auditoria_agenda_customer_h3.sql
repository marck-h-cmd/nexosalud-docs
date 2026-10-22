-- Consultas de auditoria no destructivas sobre OLTP. Requiere sqlcmd -v OLTP_DB=NexoSaludDB.
-- Una fila de colision indica un defecto a resolver en la transaccion del backend.
SELECT o.id_disponibilidad,COUNT(*) AS ReservasActivas,
 MIN(r.id_reserva) AS PrimeraReserva,MAX(r.id_reserva) AS UltimaReserva
FROM [$(OLTP_DB)].dbo.Reservas AS r
JOIN [$(OLTP_DB)].dbo.Opciones AS o ON o.id_opcion=r.id_opcion
WHERE UPPER(LTRIM(RTRIM(r.estado))) IN ('PENDIENTE','CONFIRMADA','CONFIRMADO')
GROUP BY o.id_disponibilidad HAVING COUNT(*)>1;

-- Turnos de disponibilidad invalidos o de longitud cero.
SELECT id_disponibilidad,id_profesional,id_sede,fecha,hora_inicio,hora_fin
FROM [$(OLTP_DB)].dbo.Disponibilidad WHERE hora_fin<=hora_inicio;

-- Atenciones con tiempos imposibles.
SELECT id_atencion,id_reserva,fecha_inicio,fecha_fin
FROM [$(OLTP_DB)].dbo.Atenciones WHERE fecha_inicio IS NOT NULL AND fecha_fin<fecha_inicio;

-- Reservas con mas de una atencion: anomalia de grano CUSTOMER.
SELECT id_reserva,COUNT(*) AS TotalAtenciones
FROM [$(OLTP_DB)].dbo.Atenciones GROUP BY id_reserva HAVING COUNT(*)>1;

-- Reserva reprogramada: no existe bitacora historica de su hora previa en el DDL suministrado.
SELECT r.id_reserva,r.estado,r.fecha_reserva,d.fecha,d.hora_inicio,d.hora_fin
FROM [$(OLTP_DB)].dbo.Reservas AS r
JOIN [$(OLTP_DB)].dbo.Opciones AS o ON o.id_opcion=r.id_opcion
JOIN [$(OLTP_DB)].dbo.Disponibilidad AS d ON d.id_disponibilidad=o.id_disponibilidad
WHERE UPPER(LTRIM(RTRIM(r.estado))) IN ('REPROGRAMADA','REPROGRAMADO');
