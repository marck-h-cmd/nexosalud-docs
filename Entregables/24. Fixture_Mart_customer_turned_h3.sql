-- Solo para una base de pruebas vacia. Estructura minima de dimensiones H3.
CREATE TABLE dbo.Dim_Tiempo(KeyTiempo INT PRIMARY KEY,id_fecha DATE NULL);
CREATE TABLE dbo.Dim_Hora(KeyHora INT PRIMARY KEY,id_hora INT NULL);
CREATE TABLE dbo.Dim_Sede(KeySede INT PRIMARY KEY,id_sede INT NULL);
CREATE TABLE dbo.Dim_Servicio(KeyServicio INT PRIMARY KEY,id_servicio INT NULL);
CREATE TABLE dbo.Dim_Profesional(KeyProfesional INT PRIMARY KEY,id_profesional INT NULL);
CREATE TABLE dbo.Dim_EstadoAtencion(KeyEstadoAtencion INT PRIMARY KEY,EstadoFinal VARCHAR(50) NULL,Asistencia VARCHAR(50) NULL);
CREATE TABLE dbo.Dim_Persona(KeyPersona INT PRIMARY KEY,id_persona INT NULL);
CREATE TABLE dbo.Log_Ejecucion_ETL(LogId BIGINT IDENTITY(1,1) PRIMARY KEY,Procedimiento VARCHAR(100) NOT NULL,
 BatchId VARCHAR(50) NOT NULL,TipoEvento VARCHAR(30) NOT NULL,Mensaje VARCHAR(MAX) NOT NULL,
 LineaError INT NULL,FechaRegistro DATETIME2(7) NOT NULL DEFAULT SYSDATETIME());
-- Reproduce la estructura vacia de H2; el despliegue H3 debe sustituirla sin tocar otras tablas.
CREATE TABLE dbo.Fact_AtencionCustomer(KeyTiempo INT NULL,KeyHora INT NULL,KeySede INT NULL,
 KeyServicio INT NULL,KeyProfesional INT NULL,KeyEstadoAtencion INT NULL,
 CitasEvaluables INT NULL,AtencionesRealizadas INT NULL,CitasConInasistencia INT NULL,
 TiempoEnSillonDentalMin INT NULL,AtencionesFinalizadasConformes INT NULL);
INSERT dbo.Dim_Tiempo VALUES
(0,NULL),(1,'2026-10-01'),(2,'2026-10-02'),(3,'2026-10-03'),(4,'2026-10-04'),
(5,'2026-10-05'),(6,'2026-10-20'),(7,'2026-10-06'),(8,'2026-10-07'),
(9,'2026-12-01');
INSERT dbo.Dim_Hora VALUES(0,NULL),(1,900);
INSERT dbo.Dim_Sede VALUES(0,NULL),(1,1);
INSERT dbo.Dim_Servicio VALUES(0,NULL),(1,1);
INSERT dbo.Dim_Profesional VALUES(0,NULL),(1,1);
INSERT dbo.Dim_EstadoAtencion VALUES(0,NULL,NULL),(1,'Realizado','Asistió');
INSERT dbo.Dim_Persona VALUES(0,NULL),(1,1),(2,2);
