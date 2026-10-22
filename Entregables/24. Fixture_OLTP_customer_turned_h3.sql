-- Solo para una base de pruebas vacia. Nunca ejecutar en NexoSaludDB.
CREATE TABLE dbo.Solicitudes(id_solicitud INT PRIMARY KEY,id_persona INT NOT NULL,id_servicio INT NULL);
CREATE TABLE dbo.Disponibilidad(id_disponibilidad INT PRIMARY KEY,id_sede INT NOT NULL,id_profesional INT NOT NULL,
 fecha DATE NOT NULL,hora_inicio TIME NOT NULL,hora_fin TIME NOT NULL,estado VARCHAR(20) NOT NULL);
CREATE TABLE dbo.Opciones(id_opcion INT PRIMARY KEY,id_solicitud INT NOT NULL,id_disponibilidad INT NOT NULL);
CREATE TABLE dbo.Reservas(id_reserva INT IDENTITY(1,1) PRIMARY KEY,id_persona INT NOT NULL,id_solicitud INT NOT NULL,id_opcion INT NOT NULL,
 estado VARCHAR(30) NOT NULL,confirmacion_explicita BIT NOT NULL,fecha_reserva DATETIME2 NOT NULL);
CREATE TABLE dbo.Atenciones(id_atencion INT PRIMARY KEY,id_persona INT NOT NULL,id_reserva INT NOT NULL,
 id_sede INT NOT NULL,id_servicio INT NOT NULL,id_profesional INT NOT NULL,
 fecha_atencion DATETIME2 NOT NULL,fecha_inicio DATETIME2 NULL,fecha_fin DATETIME2 NULL,
 asistencia VARCHAR(20) NOT NULL,estado_servicio VARCHAR(30) NOT NULL,
 diagnostico_basico VARCHAR(200) NULL,procedimiento_realizado VARCHAR(200) NULL,indicaciones_finales VARCHAR(500) NULL);
CREATE TABLE dbo.Seguimientos(id_seguimiento INT PRIMARY KEY,id_persona INT NOT NULL,id_atencion INT NOT NULL,
 fecha_hora DATETIME2 NOT NULL,canal VARCHAR(50) NULL,tipo VARCHAR(50) NOT NULL,
 satisfaccion TINYINT NULL,incidencia BIT NOT NULL);

INSERT dbo.Solicitudes VALUES(1,1,1),(2,1,1),(3,2,1),(4,2,1),(5,2,1),(6,2,1),(7,2,1),(8,2,1),(9,2,1);
INSERT dbo.Disponibilidad VALUES
(1,1,1,'2026-10-01','09:00','10:00','Ocupado'),(2,1,1,'2026-10-20','09:00','10:00','Ocupado'),
(3,1,1,'2026-10-03','09:00','10:00','Ocupado'),(4,1,1,'2026-10-04','09:00','10:00','Ocupado'),
(5,1,1,'2026-12-01','09:00','10:00','Ocupado'),(6,1,1,'2026-10-05','09:00','10:00','Ocupado'),
(7,1,1,'2026-10-06','09:00','10:00','Ocupado'),(8,1,1,'2026-10-07','09:00','10:00','Ocupado'),
(9,1,1,'2027-03-01','09:00','10:00','Disponible');
INSERT dbo.Opciones VALUES(1,1,1),(2,2,2),(3,3,3),(4,4,4),(5,5,5),(6,6,6),(7,7,7),(8,8,8),(9,9,9);
SET IDENTITY_INSERT dbo.Reservas ON;
INSERT dbo.Reservas(id_reserva,id_persona,id_solicitud,id_opcion,estado,confirmacion_explicita,fecha_reserva) VALUES
(1,1,1,1,'Confirmada',1,'2026-09-20'),(2,1,2,2,'Confirmada',1,'2026-10-10'),
(3,2,3,3,'No-Show',1,'2026-09-20'),(4,2,4,4,'Confirmada',1,'2026-09-20'),
(5,2,5,5,'Confirmada',1,'2026-10-10'),(6,2,6,6,'Cancelada',1,'2026-09-20'),
(7,2,7,7,'Confirmada',1,'2026-09-20'),(8,2,8,8,'Confirmada',1,'2026-09-20');
SET IDENTITY_INSERT dbo.Reservas OFF;
INSERT dbo.Atenciones VALUES
(1,1,1,1,1,1,'2026-10-01 09:00','2026-10-01 09:10','2026-10-01 09:50','Asistió','Realizado','Evaluación','Limpieza completa','Control en siete días'),
(2,1,2,1,1,1,'2026-10-20 09:00','2026-10-20 09:05','2026-10-20 09:45','Asistió','Realizado','Evaluación','Curación completa','Control en siete días'),
(7,2,7,1,1,1,'2026-10-06 09:00','2026-10-06 09:50','2026-10-06 09:10','Asistió','Realizado','Evaluación','Curación completa','Control en siete días'),
(8,2,8,1,1,1,'2026-10-07 09:00','2026-10-07 09:10','2026-10-07 09:50','Asistió','Realizado','Evaluación','Curación completa','Control en siete días'),
(9,2,8,1,1,1,'2026-10-07 09:00','2026-10-07 09:10','2026-10-07 09:50','Asistió','Realizado','Evaluación','Curación completa','Control en siete días');
INSERT dbo.Seguimientos VALUES
(1,1,1,'2026-10-02 11:00','WhatsApp','Control',5,0),
(2,2,999,'2026-10-02 11:00','WhatsApp','Control',NULL,0),
(3,2,1,'2026-10-02 11:00','WhatsApp','Control',NULL,0);
