-- ====================================================================
-- NEXOSALUD — DATA MART DIMENSIONAL (MODELO ESTRELLA CONFORMADO)
-- Hito H2: DDL Oficial de Esquemas, Dimensiones Conformadas y Hechos
-- Responsable: Integrante 2 — Marck Alessandro Hermenegildo Pacheco
-- Rol: Diseñador Dimensional, Especialista en Dimensiones y Arquitecto ETL
-- Motor: Microsoft SQL Server 2019 / 2022
-- Fecha de Emisión: Octubre de 2026
-- ====================================================================

-- 1. CREACIÓN Y CONFIGURACIÓN DE LA BASE DE DATOS ANALÍTICA
-- ====================================================================
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NexoSalud_Mart')
BEGIN
    CREATE DATABASE NexoSalud_Mart;
END;
GO

USE NexoSalud_Mart;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ====================================================================
-- 2. DROP PREVIO DE TABLAS DE HECHOS (PARA RECONSTRUCCIÓN LIMPIA)
-- ====================================================================
IF OBJECT_ID('dbo.Fact_AtencionCustomer', 'U') IS NOT NULL DROP TABLE dbo.Fact_AtencionCustomer;
IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NOT NULL DROP TABLE dbo.Fact_GestionPayer;
IF OBJECT_ID('dbo.Fact_NegociacionLead', 'U') IS NOT NULL DROP TABLE dbo.Fact_NegociacionLead;
IF OBJECT_ID('dbo.Fact_CaptacionBuyer', 'U') IS NOT NULL DROP TABLE dbo.Fact_CaptacionBuyer;
GO

-- ====================================================================
-- 3. DROP PREVIO DE DIMENSIONES
-- ====================================================================
IF OBJECT_ID('dbo.Dim_EstadoAtencion', 'U') IS NOT NULL DROP TABLE dbo.Dim_EstadoAtencion;
IF OBJECT_ID('dbo.Dim_Cobro', 'U') IS NOT NULL DROP TABLE dbo.Dim_Cobro;
IF OBJECT_ID('dbo.Dim_Pasarela', 'U') IS NOT NULL DROP TABLE dbo.Dim_Pasarela;
IF OBJECT_ID('dbo.Dim_Negociador', 'U') IS NOT NULL DROP TABLE dbo.Dim_Negociador;
IF OBJECT_ID('dbo.Dim_Profesional', 'U') IS NOT NULL DROP TABLE dbo.Dim_Profesional;
IF OBJECT_ID('dbo.Dim_Pagador', 'U') IS NOT NULL DROP TABLE dbo.Dim_Pagador;
IF OBJECT_ID('dbo.Dim_TipoPersona', 'U') IS NOT NULL DROP TABLE dbo.Dim_TipoPersona;
IF OBJECT_ID('dbo.Dim_EstadoRegistro', 'U') IS NOT NULL DROP TABLE dbo.Dim_EstadoRegistro;
IF OBJECT_ID('dbo.Dim_Fuente', 'U') IS NOT NULL DROP TABLE dbo.Dim_Fuente;
IF OBJECT_ID('dbo.Dim_Canal', 'U') IS NOT NULL DROP TABLE dbo.Dim_Canal;
IF OBJECT_ID('dbo.Dim_Servicio', 'U') IS NOT NULL DROP TABLE dbo.Dim_Servicio;
IF OBJECT_ID('dbo.Dim_Sede', 'U') IS NOT NULL DROP TABLE dbo.Dim_Sede;
IF OBJECT_ID('dbo.Dim_Hora', 'U') IS NOT NULL DROP TABLE dbo.Dim_Hora;
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NOT NULL DROP TABLE dbo.Dim_Tiempo;
GO

-- ====================================================================
-- 4. CREACIÓN DE TABLAS DIMENSIONALES (CONFORMADAS Y DE CATÁLOGO)
-- ====================================================================

-- 4.1 Dimensión Tiempo (Conformada para las 4 etapas)
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo INT IDENTITY(1,1) PRIMARY KEY, 
    id_fecha DATE NOT NULL,
    Anio INT NOT NULL,
    Trimestre INT NOT NULL,
    Mes INT NOT NULL,
    Dia INT NOT NULL
);
GO

-- 4.2 Dimensión Hora (Para PAYER y CUSTOMER)
CREATE TABLE dbo.Dim_Hora (
    KeyHora INT IDENTITY(1,1) PRIMARY KEY,
    id_hora INT NOT NULL,
    Turno VARCHAR(50),      -- Mañana, Tarde, Noche
    Hora INT,
    Minuto INT
);
GO

-- 4.3 Dimensión Sede (Conformada para las 4 etapas)
CREATE TABLE dbo.Dim_Sede (
    KeySede INT IDENTITY(1,1) PRIMARY KEY,
    id_sede INT NULL,       -- Business Key para el MERGE
    Sede VARCHAR(100),
    Distrito VARCHAR(100),
    Zona VARCHAR(100)
);
GO

-- 4.4 Dimensión Servicio (Conformada para las 4 etapas)
CREATE TABLE dbo.Dim_Servicio (
    KeyServicio INT IDENTITY(1,1) PRIMARY KEY,
    id_servicio INT NULL,   -- Business Key para el MERGE
    ServicioOdontologico VARCHAR(100),
    Categoria VARCHAR(100),
    Procedimiento VARCHAR(100)
);
GO

-- 4.5 Dimensión Canal (Para BUYER)
CREATE TABLE dbo.Dim_Canal (
    KeyCanal INT IDENTITY(1,1) PRIMARY KEY,
    id_canal INT NULL,      -- Business Key para el MERGE
    NombreCanal VARCHAR(50),
    TipoMedio VARCHAR(50)   -- Orgánico, Paga, Directo, etc.
);
GO

-- 4.6 Dimensión Fuente / Campaña (Para BUYER y PAYER)
CREATE TABLE dbo.Dim_Fuente (
    KeyFuente INT IDENTITY(1,1) PRIMARY KEY,
    id_fuente INT NULL,     -- Business Key para el MERGE
    id_campana INT NULL,    -- Business Key para el MERGE
    TipoOrigen VARCHAR(100),
    Campana VARCHAR(150)
);
GO

-- 4.7 Dimensión Estado del Registro (Para BUYER)
CREATE TABLE dbo.Dim_EstadoRegistro (
    KeyEstadoRegistro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoCalidad VARCHAR(50),      -- Válido, Incompleto, Duplicado
    AutorizacionContacto VARCHAR(2) -- SI / NO
);
GO

-- 4.8 Dimensión Tipo Persona / Perfil Buyer (Para BUYER)
CREATE TABLE dbo.Dim_TipoPersona (
    KeyTipoPersona INT IDENTITY(1,1) PRIMARY KEY,
    id_persona INT NULL,    -- Business Key para el MERGE
    Ocupacion VARCHAR(100),
    RangoEdad VARCHAR(50)
);
GO

-- 4.9 Dimensión Pagador (Para PAYER, versión extendida de la persona)
CREATE TABLE dbo.Dim_Pagador (
    KeyPagador INT IDENTITY(1,1) PRIMARY KEY,
    id_persona INT NULL,    -- Business Key para el MERGE
    Ocupacion VARCHAR(100),
    RangoEdad VARCHAR(50),
    EstadoCivil VARCHAR(50),
    NivelIngreso VARCHAR(50)
);
GO

-- 4.10 Dimensión Profesional (Para LEAD y CUSTOMER)
CREATE TABLE dbo.Dim_Profesional (
    KeyProfesional INT IDENTITY(1,1) PRIMARY KEY,
    id_profesional INT NULL, -- Business Key para el MERGE
    Odontologo VARCHAR(100),
    EspecialidadPrincipal VARCHAR(100)
);
GO

-- 4.11 Dimensión Negociador (Para LEAD)
CREATE TABLE dbo.Dim_Negociador (
    KeyNegociador INT IDENTITY(1,1) PRIMARY KEY,
    id_usuario INT NULL,     -- Business Key para el MERGE
    NombreNegociador VARCHAR(100)
);
GO

-- 4.12 Dimensión Pasarela (Para PAYER)
CREATE TABLE dbo.Dim_Pasarela (
    KeyPasarela INT IDENTITY(1,1) PRIMARY KEY,
    MetodoPago VARCHAR(50),      -- Yape, Transferencia, TC
    EntidadFinanciera VARCHAR(100),
    TipoMedio VARCHAR(50)        -- Billetera, Banco, Web
);
GO

-- 4.13 Dimensión Cobro (Para PAYER)
CREATE TABLE dbo.Dim_Cobro (
    KeyCobro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoPago VARCHAR(50),      -- Validado, Rechazado, Pendiente
    ComprobanteAdjunto VARCHAR(2) -- SI / NO
);
GO

-- 4.14 Dimensión Estado Atención (Para CUSTOMER)
CREATE TABLE dbo.Dim_EstadoAtencion (
    KeyEstadoAtencion INT IDENTITY(1,1) PRIMARY KEY,
    EstadoFinal VARCHAR(50),     -- Programado, Atendido, Cancelado
    Asistencia VARCHAR(50)       -- Asistió, No Asistió
);
GO

-- ====================================================================
-- 5. CREACIÓN DE TABLAS DE HECHOS (FACT TABLES)
-- ====================================================================

-- 5.1 Hecho: CAPTACIÓN BUYER
CREATE TABLE dbo.Fact_CaptacionBuyer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyCanal INT FOREIGN KEY REFERENCES dbo.Dim_Canal(KeyCanal),
    KeyFuente INT FOREIGN KEY REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyTipoPersona INT FOREIGN KEY REFERENCES dbo.Dim_TipoPersona(KeyTipoPersona),
    KeyEstadoRegistro INT FOREIGN KEY REFERENCES dbo.Dim_EstadoRegistro(KeyEstadoRegistro),
    
    -- Medidas
    ContactosRegistrados INT DEFAULT 0,
    ContactosUtilizables INT DEFAULT 0,
    ConversionesALead INT DEFAULT 0,
    TiempoConversionDias INT DEFAULT 0,
    CostoAtribuidoCaptacion DECIMAL(10,2) DEFAULT 0.00
);
GO

-- 5.2 Hecho: NEGOCIACIÓN LEAD
CREATE TABLE dbo.Fact_NegociacionLead (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyProfesional INT FOREIGN KEY REFERENCES dbo.Dim_Profesional(KeyProfesional),
    KeyNegociador INT FOREIGN KEY REFERENCES dbo.Dim_Negociador(KeyNegociador),
    
    -- Medidas
    LeadsCohorteEvaluable INT DEFAULT 0,
    LeadsConvertidosPayer14Dias INT DEFAULT 0,
    LeadsRequierenRespuesta INT DEFAULT 0,
    LeadsRespuestaUtil15Min INT DEFAULT 0,
    LeadsResultadoFinal INT DEFAULT 0,
    LeadsAbandonados INT DEFAULT 0
);
GO

-- 5.3 Hecho: GESTIÓN PAYER
CREATE TABLE dbo.Fact_GestionPayer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyHora INT FOREIGN KEY REFERENCES dbo.Dim_Hora(KeyHora),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyFuente INT FOREIGN KEY REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyPasarela INT FOREIGN KEY REFERENCES dbo.Dim_Pasarela(KeyPasarela),
    KeyPagador INT FOREIGN KEY REFERENCES dbo.Dim_Pagador(KeyPagador),
    KeyCobro INT FOREIGN KEY REFERENCES dbo.Dim_Cobro(KeyCobro),
    
    -- Medidas
    PagosRegistrados INT DEFAULT 0,
    PagosValidados INT DEFAULT 0,
    PagosRechazados INT DEFAULT 0,
    ConversionesACustomer INT DEFAULT 0,
    ImporteTotalCobro DECIMAL(10,2) DEFAULT 0.00,
    CostoTotalTransacciones DECIMAL(10,2) DEFAULT 0.00,
    TiempoTotalValidacionMin INT DEFAULT 0
);
GO

-- 5.4 Hecho: ATENCIÓN CUSTOMER
CREATE TABLE dbo.Fact_AtencionCustomer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyHora INT FOREIGN KEY REFERENCES dbo.Dim_Hora(KeyHora),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyProfesional INT FOREIGN KEY REFERENCES dbo.Dim_Profesional(KeyProfesional),
    KeyEstadoAtencion INT FOREIGN KEY REFERENCES dbo.Dim_EstadoAtencion(KeyEstadoAtencion),
    
    -- Medidas
    CitasEvaluables INT DEFAULT 0,
    AtencionesRealizadas INT DEFAULT 0,
    CitasConInasistencia INT DEFAULT 0,
    TiempoEnSillonDentalMin INT DEFAULT 0,
    AtencionesFinalizadasConformes INT DEFAULT 0
);
GO

PRINT 'Esquema NexoSalud_Mart: 14 dimensiones y 4 tablas de hechos creadas exitosamente.';
GO
