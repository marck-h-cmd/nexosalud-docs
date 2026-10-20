UNIVERSIDAD NACIONAL DE TRUJILLO

NEXOSALUD

Auditoría técnico-funcional, mejora del sistema y plan de poblamiento del Data Mart

Plan de trabajo secuencial y equilibrado para siete integrantes

Curso: Inteligencia de Negocios | Proyecto odontológico | Octubre de 2026

# 1\. Propósito, alcance y límites

Este documento convierte el informe académico, los anexos SQL y el archivo ANÁLISIS_COMPLETO.md en un plan de implementación verificable. No se recibió el repositorio ejecutable, esquema Prisma migrado, base de datos con registros reales ni resultados de pruebas: las observaciones relativas a endpoints son hipótesis reportadas en el análisis previo, no fallos reproducidos. Tampoco se afirma que se hayan ejecutado ETL ni cargado tablas.

Convenciones de evidencia: \[I\] Informe NexoSalud; \[A\] Anexos con entrevista y scripts SQL; \[T\] ANÁLISIS_COMPLETO.md; \[P\] propuesta técnica derivada. Se evita atribuir al sponsor requisitos que no expresó.

# 2\. Diagnóstico ejecutivo

| Nivel   | Observación                                                                               | Acción inmediata                                              |
| ------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Crítico | Modelo de 4 hechos sin clave ni grano declarado \[A\]                                     | Diseñar grano y clave natural; carga idempotente              |
| Crítico | Pago adelantado obligatorio contradice entrevista: clínica sin adelantos \[I,A\]          | Separar reserva, confirmación y política de pago configurable |
| Crítico | TURNED ambiguo entre postventa y paciente perdido \[I,T\]                                 | Definir estados y eventos sin sobrecargar etapa               |
| Crítico | No hay hecho de ingresos/gastos ni rentabilidad \[A\], pese a prioridad del sponsor \[A\] | Añadir hechos de movimientos de caja y gastos / conciliación  |
| Alto    | Cuatro hechos omiten trazabilidad de fuente transaccional \[A\]                           | Agregar IDs degenerados, auditoría y reglas ETL               |
| Alto    | Medidas mezclan eventos y cohortes \[A\]                                                  | Cohortes fijadas y denominadores explícitos                   |
| Alto    | Capacidad, reprogramación y doble reserva \[A,I\]                                         | Transacciones/índices, pruebas de concurrencia                |
| Alto    | Falta evidencia de funcionamiento de rutas reportadas \[T\]                               | Reproducción con código y tests                               |

# 3\. Inconsistencias comprobadas y soluciones de negocio

## 3.1 Política de cobro no alineada con Luxedent

Diagnóstico (Crítica): El informe dice que PAYER → CUSTOMER requiere acreditar el pago; en entrevista el odontólogo indica "no damos adelantos", y señala reprogramaciones frecuentes \[I,A\].

Corrección: Configurar politica_reserva_por_sede/servicio: sin_anticipo, anticipo_opcional, anticipo_requerido. No obligar pago para confirmar citas en el escenario sin anticipo. Separar "reserva confirmada", "atención completada" y "pago validado"; evitar que CUSTOMER equivalga a pago cuando el proceso real no lo exige.

Verificación/aceptación: Reservar y atender un caso sin anticipo; cobrar posteriormente sin bloqueo, y verificar historial completo.

## 3.2 Semántica contradictoria de TURNED

Diagnóstico (Crítica): Informe: TURNED significa postventa, fidelización y seguimiento; archivo técnico: "paciente perdido" \[I,T\].

Corrección: Conservar TURNED como postatención, si esa es la decisión del proyecto; introducir estado de relación (activo, inactivo, perdido, reactivado) y estado de solicitud independiente. Documentar transición de reactivación como nueva solicitud de una persona existente.

Verificación/aceptación: Una persona con 2 solicitudes y 2 atenciones mantiene identidad; la primera solicitud no pierde historial.

## 3.3 Identidad persona vs. intención comercial

Diagnóstico (Crítica): El análisis técnico aconseja deduplicar por teléfono+canal+fuente \[T\]; esto produciría personas duplicadas por cambio de canal.

Corrección: Identidad estable por id_persona y coincidencias normalizadas con resolución manual; canal/fuente/campaña pertenecen al contacto, interacción, solicitud o atribución, no definen una nueva persona. DNI solo si procede y con protección adecuada.

Verificación/aceptación: Un mismo teléfono desde WhatsApp y Web se vincula a persona única, conservando dos interacciones y dos solicitudes.

## 3.4 Atención clínica y BI con distinta sensibilidad

Diagnóstico (Crítica): Las tablas Atenciones y PersonaSaludOdontologica contienen alergias, antecedentes, diagnóstico e indicaciones \[A\].

Corrección: No replicar texto clínico libre ni identificadores personales innecesarios al mart; crear dimensión paciente pseudonimizada solo si imprescindible, permisos mínimos, protección en tránsito/reposo, registros de acceso y política de retención conforme al marco aplicable.

Verificación/aceptación: Cuenta BI no consulta anamnesis; reportes agregados no revelan datos de pacientes.

## 3.5 Métricas reales del sponsor no cubiertas

Diagnóstico (Alta): En la entrevista se priorizan ingresos y gastos, valor de tratamientos, repetición de pacientes y comparación entre meses; se usan Excel y WhatsApp \[A\].

Corrección: Crear data mart financiero operativo de cobros efectivamente recibidos, gastos, prestaciones realizadas y pacientes nuevos/recurrentes; diferenciar ventas pactadas, producción clínica, caja y margen (este último solo con costos completos).

Verificación/aceptación: Tablero concilia ventas, recaudación, atenciones y gastos; mes de servicio puede diferir del mes de cobro.

## 3.6 Atribución de fuente y campaña

Diagnóstico (Alta): Dim_Fuente combina id_fuente e id_campana mientras Personas registra campaña/canal de origen; riesgo de fanout y atribución arbitraria \[A\].

Corrección: Separar Dim_Fuente y Dim_Campana, establecer primer toque/último toque según KPI y modelar interacción multitoque como puente si se requiere. No duplicar costos de campaña por cada contacto.

Verificación/aceptación: Total gastos campaña no cambia al desglosar por contactos; se detectan fuentes desconocidas.

## 3.7 Tarifas y vigencias

Diagnóstico (Alta): Tarifas tiene inicio y fin de vigencia \[A\]; las opciones guardan precio_ofrecido \[A\].

Corrección: Registrar importe ofertado histórico como hecho; impedir superposiciones por servicio/sede cuando aplique; no recalcular cobros históricos con precio vigente.

Verificación/aceptación: Cambio de tarifa no altera cotización o transacción anterior.

# 4\. Revisión técnica del esquema SQL dimensional

## 4.1 Hechos sin identificador propio ni clave del evento

Diagnóstico (Crítica): Fact_CaptacionBuyer, Fact_NegociacionLead, Fact_GestionPayer y Fact_AtencionCustomer son filas de dimensiones y medidas sin PK, unique del evento, id de origen ni fecha de carga \[A\].

Corrección: Adicionar KeyFact bigint identity PK; source_id estable (id_persona / id_solicitud / id_pago / id_atencion según grano); índice único (sistema_origen, source_id y tipo_evento si procede); BatchId y fecha_carga.

Verificación/aceptación: Dos ejecuciones de la carga producen el mismo COUNT y SUM.

## 4.2 Granos mezclados

Diagnóstico (Crítica): Fact_CaptacionBuyer mezcla contactos y conversiones; Fact_NegociacionLead mezcla respuestas, abandono y conversión 14 días \[A\].

Corrección: Diseñar hechos atómicos por evento y snapshot de cohorte separado; no multiplicar conversiones por actualizaciones.

Verificación/aceptación: Cambiar estado histórico actualiza snapshot, sin duplicar primer contacto.

## 4.3 Dimensiones sin natural key única ni registro desconocido

Diagnóstico (Alta): Dim_Sede, Dim_Servicio, Dim_Canal y otras tienen id_sede/id_servicio/etc. nullable sin UNIQUE; los hechos tienen FKs no marcadas NOT NULL \[A\].

Corrección: Definir claves naturales no nulas para registros de negocio, UNIQUE según política SCD; insertar miembro desconocido con surrogate 0 o -1; FK NOT NULL donde corresponda.

Verificación/aceptación: ETL resuelve cada dimensión a una única clave; ninguna referencia rota.

## 4.4 Dim_Hora potencialmente no poblada y claves inconsistentes

Diagnóstico (Alta): Dim_Hora usa KeyHora como HHMM y Dim_Tiempo YYYYMMDD, pero el anexo solo define tablas \[A\].

Corrección: Poblar calendarios controlados y hora a granularidad documentada; asegurar minutos válidos y zona horaria Lima en extracción.

Verificación/aceptación: Claves de fecha/hora de todas las filas encuentran coincidencia.

## 4.5 Dim_TipoPersona y Dim_Pagador redundantes

Diagnóstico (Media): Ambas usan id_persona como business key con atributos que pueden cambiar y están repartidas entre hechos \[A\].

Corrección: Crear dimensión persona comercial anonimizada conformada, o documentar por qué se requieren roles distintos; implementar SCD2 solo para atributos históricos relevantes.

Verificación/aceptación: Cambios ocupacionales no reescriben reportes históricos si se elige SCD2.

## 4.6 Dim_Pasarela y Dim_Cobro no tienen ID de origen estable

Diagnóstico (Alta): Se usan atributos textuales de pago y estado \[A\].

Corrección: Construir catálogos canónicos con clave única compuesta; reconocer diferencias entre método, entidad y estado; estados de pago historizados como eventos cuando se estudian transiciones.

Verificación/aceptación: No se crean claves nuevas por diferencias de mayúsculas o tildes.

## 4.7 Medidas inexistentes en OLTP

Diagnóstico (Crítica): El hecho payer incluye CostoTotalTransacciones; Dim_Pagador incluye EstadoCivil y NivelIngreso, campos no visibles en Personas/Pagos del script \[A\].

Corrección: No inventar valores: marcar "no disponible" y excluir temporalmente el KPI, o añadir captura con fundamento, permisos y validación.

Verificación/aceptación: Diccionario de mapeo identifica fuente concreta de cada atributo y medida.

## 4.8 Moneda, reversiones y pagos parciales

Diagnóstico (Alta): Pagos guarda importe y estado, pero no moneda ni comisión explícita en tabla mostrada \[A\]; el sponsor menciona implantes cotizados en dólares \[A\].

Corrección: Añadir moneda y tipo de cambio a la operación cuando se soporte operación multimoneda; distinguir cobros, devoluciones, reversos, anticipos y saldo; no convertir indiscriminadamente "validado" en ingreso del servicio.

Verificación/aceptación: Cuadre por moneda y período; una reversión corrige caja sin borrar historia.

## 4.9 Solapamiento de turnos y reprogramaciones

Diagnóstico (Crítica): Disponibilidad modela franjas y Reservas guarda estado/expiración \[A\], pero el DDL mostrado no impone exclusión de solapamientos.

Corrección: Transacciones SERIALIZABLE o bloqueo de slot, índice único filtrado para reserva activa cuando corresponda, validaciones hora_inicio<hora_fin y registro explícito de reprogramaciones.

Verificación/aceptación: Dos reservas concurrentes no toman el mismo recurso; se preserva el historial de cambios.

## 4.10 Falta de medición TURNED

Diagnóstico (Alta): Anexo solo crea cuatro hechos y no un quinto para seguimientos/retención \[A\].

Corrección: Proponer Fact_SeguimientoTurned por seguimiento y Fact_Reactivacion por nueva solicitud, o una tabla de eventos de journey reutilizable.

Verificación/aceptación: Se calculan tasas de seguimiento y retorno sin duplicar pacientes.

# 5\. Hallazgos del análisis de software: estado de verificación

El archivo \[T\] menciona React/TypeScript/Vite, Express/Prisma/SQL Server; los archivos buyer.routes.ts, buyerSchema.ts, lead.routes.ts, NegotiatorAgentService y componentes React no fueron adjuntados. Por ello NO se declara su fallo como reproducido.

| Hallazgo reportado \[T\]              | Procedimiento de auditoría                         | Corrección condicionada                               |
| ------------------------------------- | -------------------------------------------------- | ----------------------------------------------------- |
| isNewPersonConfirmed ausente del Zod  | Verificar definición, parsing y tests de /register | Validación consistente cliente/servidor y rechazo 400 |
| pre-reserve sin notificación          | Seguir transacción, colas y envíos en pruebas      | Outbox idempotente; enviar tras commit                |
| historial de interacciones no visible | Revisar Buyer/Lead UI y consulta de backend        | Timeline paginada por persona/solicitud               |
| preferencias no aplicadas             | Trazar datos de PersonaPreferencias a ofertas      | Selección opcional sin alterar consentimiento         |
| WhatsApp estático                     | Verificar proveedor, plantillas y consentimiento   | Integración real o simulador claramente etiquetado    |
| índices EventosEtapa insuficientes    | Examinar execution plans y uso real                | Índices compuestos medidos                            |
| scoring y nurturing ausentes          | Contrastar requisitos y presupuesto                | Primero motor de reglas auditable, después IA         |

Advertencias sobre sugerencias de \[T\]: no usar numero(9) en CREATE INDEX de SQL Server (sintaxis inválida); índice sobre columna numero completa/normalizada. Tampoco exigir autorización promocional para prestar el servicio; separar consentimiento operativo y marketing. Evitar aprobar descuentos o agendar automáticamente sin autorización y política comercial.

# 6\. Modelo dimensional objetivo: granos, fuentes y métricas

| Hecho / prioridad           | Grano inequívoco                                                     | Origen OLTP                                    | Métricas y precauciones                                                             |
| --------------------------- | -------------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------- |
| Fact_CaptacionBuyer / P0    | 1 persona registrada (cohorte) o 1 contacto si hay eventos separados | Personas; Interacciones; EventosEtapa          | 1 registro, utilizable; conversión derivada por cohorte sin sumar eventos repetidos |
| Fact_NegociacionLead / P0   | 1 solicitud; evento de respuesta aparte si se requiere               | Solicitudes; Opciones; Reservas; EventosEtapa  | solicitudes, primera respuesta, reserva; tasa a 14 días cohortes maduras            |
| Fact_GestionPayer / P0      | 1 pago id_pago, no 1 reserva                                         | Pagos; Reservas; Opciones; Solicitudes         | importe según estado, validado, rechazado; reversión exige evento adicional         |
| Fact_AtencionCustomer / P0  | 1 atención id_atencion; ausencias pueden exigir hecho 1 reserva/cita | Atenciones; Reservas; Opciones; Disponibilidad | atendidos, duración, conformidad; faltas por reserva sin atención                   |
| Fact_SeguimientoTurned / P1 | 1 seguimiento id_seguimiento                                         | Seguimientos; Atenciones; Personas             | contactos, resultado, retorno; no confundir cita con paciente                       |
| Fact_MovimientoCaja / P1    | 1 movimiento financiero confirmado                                   | Pagos + futuras devoluciones/gastos            | cobros netos reales por fecha de caja; nuevos registros requeridos                  |
| Fact_GastoOperativo / P1    | 1 gasto/compra                                                       | GastosCampana; otras fuentes pendientes        | gasto real, categoría; no imputar costos sin datos                                  |

Dimensionamiento recomendado: Dim_Tiempo y Dim_Hora conformadas; Dim_Sede, Dim_Servicio, Dim_Profesional, Dim_Canal, Dim_Fuente y Dim_Campana; Dim_EstadoPago y Dim_EstadoAtencion; Dim_PersonaAnonimizada solo si se necesita análisis de cohortes. Mantener rol de fecha diferenciado (fecha registro, reserva, pago, servicio) mediante FKs separadas si un hecho requiere comparar distintas fechas.

# 7\. Procedimiento obligatorio para poblar hechos sin duplicados

## 7.1 Congelar contratos y respaldo

Clonar BD OLTP y mart en entorno de desarrollo; versionar scripts; fijar definición de eventos, PK de origen y reglas de anulación. No cargar sobre producción sin validación.

## 7.2 Perfilamiento y matriz de correspondencias

SQL de conteos, NULL, duplicados, estados, fechas, importes y claves huérfanas. Documento origen.campo → transformación → dimensión/hecho → validación.

## 7.3 Crear y poblar dimensiones primero

Calendario/hora, catálogos, dimensiones conformadas, miembro desconocido. UPSERT por clave de negocio; definir Type 1/Type 2 y vigencias.

## 7.4 Extraer y transformar eventos con staging

stg_Personas, stg_Solicitudes, stg_Pagos, stg_Atenciones; normalizar códigos y estados, convertir fechas, deduplicar por PK de origen y comprobar joins 1:1 o 1:N intencionados.

## 7.5 Cargar hechos atómicos idempotentes

Usar INSERT SELECT WHERE NOT EXISTS en transacción, con UNIQUE índice sobre fuente + ID y captura de errores; para hechos mutables aplicar UPDATE por fuente sin generar nuevas filas.

## 7.6 Calcular cohortes y snapshots

Congelar fecha de alta al inicio del período, exigir ventana completa de 14 días, tener denominador de elegibles y no sumar la misma conversión por reporte diario.

## 7.7 Conciliar y auditar

Comparar count distinct source_id OLTP vs. fact; SUM importe y faltantes, nulos; repetir ETL, validar estabilidad; producir bitácora BatchId de registros insertados/actualizados/rechazados.

# 7.8 Patrón T-SQL recomendado (adaptar tras definir columnas)

```
-- EJEMPLO: 1 fila por id_pago. Requiere columna id_pago_origen y UNIQUE.
BEGIN TRAN;
INSERT INTO dbo.Fact_GestionPayer
  (id_pago_origen, KeyTiempo, KeyCobro, PagosRegistrados, ImporteTotalCobro)
SELECT p.id_pago, CONVERT(int,CONVERT(char(8),p.fecha_registro,112)),
       dc.KeyCobro, 1,
       CASE WHEN p.estado='VALIDATED' THEN p.importe ELSE 0 END
FROM NexoSaludDB.dbo.Pagos p
JOIN dbo.Dim_Cobro dc ON dc.EstadoPago=p.estado
WHERE NOT EXISTS (
 SELECT 1 FROM dbo.Fact_GestionPayer f WITH (UPDLOCK,HOLDLOCK)
 WHERE f.id_pago_origen=p.id_pago
);
COMMIT;
-- NOTA: solo ejemplo ilustrativo; para cambios de estado hay que actualizar
-- la fila del hecho o guardar eventos históricos. Aún faltan otras FKs.
```

# 7.9 Pruebas mínimas por cada tabla de hechos

- Poblamiento inicial: igualdad entre registros elegibles de origen y filas destino, considerando reglas de rechazo.
- Rerun: ejecutar carga dos veces; no cambia el número de filas ni se multiplican medidas.
- Update: cambiar estado de pago y volver a cargar; se actualiza/reversa métrica conforme a política.
- Delete lógico: transacciones anuladas mantienen trazabilidad histórica.
- Calidad: no FK huérfana, no IDs de origen duplicados y todo NULL justificado.
- Finanzas: el monto validado cuadra por ID, moneda y corte temporal; no se suman opciones cotizadas como cobros.
- Operación: reserva no asistida figura en hechos de citas, aunque no tenga Atenciones.

# 8\. KPIs: definiciones para evitar resultados engañosos

| Indicador                 | Definición acordable y unidad                                                         | Condición                                                               |
| ------------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Conversión Buyer→Lead     | Personas de cohorte Buyer con primera solicitud calificada / personas Buyer elegibles | Fijar fecha de cohorte y reglas de calificación                         |
| Conversión Lead→Payer 14d | Solicitudes cohorte con reserva/compromiso dentro de 14d / solicitudes elegibles      | Solo cohortes que ya cumplieron 14 días; redefinir PAYER si no anticipo |
| Primera respuesta ≤15min  | Solicitudes respondidas en ≤15min / solicitudes que requieren respuesta               | Restar timestamps válidos; ausentes se cuentan como no cumplidas        |
| No-show                   | Citas confirmadas sin asistencia / citas confirmadas evaluables                       | Excluir futuras; definir cancelaciones y reprogramaciones               |
| Ingreso de caja           | Suma cobros acreditados menos devoluciones efectivas                                  | Por fecha de cobro, no por fecha de atención                            |
| Producción odontológica   | Importe de servicios prestados según tarifa/venta histórica                           | Separada del ingreso en caja y sin doble conteo                         |
| Ticket medio              | Valor facturado o cobrado / número de transacciones o pacientes                       | Etiquetar inequívocamente denominador                                   |
| Recompra/retorno          | Pacientes con nueva atención en ventana / pacientes elegibles previos                 | Pacientes únicos y ventana explícita                                    |
| Gasto campañas y CAC      | Gasto atribuible / número de clientes nuevos atribuidos                               | Reglas de atribución y costos reales necesarios                         |

# 9\. Mejoras que elevan el proyecto de Inteligencia de Negocios

| Nivel          | Mejora                                                                    | Entregable evaluable                                          |
| -------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Imprescindible | Dashboard ejecutivo por ingresos, gastos, atención, recurrencia y no-show | Power BI/Frontend con filtros por fecha, servicio, sede       |
| Imprescindible | Pipeline incremental trazable, reconciliado, idempotente                  | SQL versionado + auditoría y reportes de calidad              |
| Alto           | Drill-through de KPI a evento pseudonimizado                              | Vista detallada sin datos clínicos sensibles                  |
| Alto           | Análisis de cohortes y embudo por antigüedad                              | Comparación mensual y conversión a 14/30 días                 |
| Alto           | Simulación "qué pasa si" de capacidad / cancelaciones                     | Escenarios transparentes, no predicción falsa                 |
| Medio          | Forecast de demanda/recaudación con intervalos                            | Baseline estacional; MAE/MAPE y comparación con modelo simple |
| Medio          | Motor de alertas explicables                                              | Reglas SQL + destinatario + evidencia + bitácora              |
| Opcional       | Scoring de leads validado y supervisado                                   | Variables autorizadas, sesgo/calibración y versión del modelo |
| Opcional       | Integración de notificaciones con outbox                                  | No duplicar envíos y respetar autorización comercial          |

# 10\. Plan consecutivo con siete responsables

Criterio de equidad: cada integrante tiene una línea principal de similar esfuerzo estimado (aprox. 18–22 horas), más revisión cruzada. Los hitos tienen dependencias; las actividades de diseño y preparación pueden solaparse, pero una fase no se cierra sin la aceptación de la anterior. Nombres tomados de la portada del informe \[I\]; el equipo puede reasignarlos.

## 1\. Germaín Alexander Cruz Vargas

Responsabilidad: Diagnóstico de datos y reglas de negocio | Esfuerzo estimado: 20 h | Hito: H1: Auditoría y contratos

1\. Revisar entrevista, informe, diferencias pago/etapas; construir matriz requisito→realidad→decisión.

2\. Perfilar Personas, Solicitudes, EventosEtapa, Reservas, estados, conteos y duplicados.

3\. Definir identidad única, eventos BUYER/LEAD y política de cohorte; diseñar datasets de prueba.

4\. Entregar diccionario del dominio, mapa de estados, SQL de calidad y acta de reglas aprobadas.

Entregables comprobables: Matriz de reglas, consultas de profiling, 10 casos de prueba de negocio.

Dependencias y coordinación: Todos validan reglas; entrega a 2, 3, 4 y 5.

## 2\. Marck Alessandro Hermenegildo Pacheco

Responsabilidad: Modelo dimensional, dimensiones y arquitectura ETL | Esfuerzo estimado: 21 h | Hito: H2: Esquema/Dimensiones

1\. Inventariar las dimensiones del anexo; resolver natural keys, desconocidos y SCD.

2\. Crear migración de hechos con PK/source_id/unique y catálogo Dim_Campana.

3\. Implementar carga de Dim_Tiempo, Dim_Hora y dimensiones conformadas, con pruebas de integridad.

4\. Documentar grano de cada hecho, rol de fechas y mapeos OLTP→mart; entregar diagrama estrella.

Entregables comprobables: DDL versionado, diagrama, scripts dimensiones, conciliación claves.

Dependencias y coordinación: Depende de reglas 1; habilita hechos 3,4,5.

## 3\. Mario Antonio Martinez Dominguez

Responsabilidad: ETL BUYER y LEAD, embudo y calidad | Esfuerzo estimado: 20 h | Hito: H3: Captación/Negociación

1\. Construir staging de Personas, Interacciones, Solicitudes y EventosEtapa.

2\. Poblar Fact_CaptacionBuyer por grano pactado y Fact_NegociacionLead por solicitud sin duplicados.

3\. Calcular cohortes 14 días, primera respuesta 15 minutos y reportes por fuente.

4\. Ejecutar pruebas rerun, nulos, tardíos y reconciliación; entregar evidencias SQL.

Entregables comprobables: 2 ETL, procedimientos y suite de pruebas de captación.

Dependencias y coordinación: Requiere dimensiones 2 y estado negocio 1.

## 4\. Jesús Daniel Ordóñez Ugarte

Responsabilidad: ETL PAYER y conciliación monetaria | Esfuerzo estimado: 21 h | Hito: H3: Pagos/Caja

1\. Analizar Pagos, Reservas y opciones; documentar pago parcial, reversión y moneda faltante.

2\. Poblar Fact_GestionPayer por id_pago y claves con casos sin anticipo.

3\. Diseñar e implementar hecho de movimiento de caja si existe la fuente; no simular gastos no disponibles.

4\. Conciliar totales por día/estado/moneda y probar actualización de estados y repetición ETL.

Entregables comprobables: ETL pagos, conciliación, matriz de reglas monetarias y casos sin adelanto.

Dependencias y coordinación: Requiere dimensiones 2; coordina con 5 y 6.

## 5\. Alexis Gean Gerardo Vigo Huayán

Responsabilidad: ETL CUSTOMER y TURNED, agenda y concurrencia | Esfuerzo estimado: 21 h | Hito: H3: Atención/Retención

1\. Revisar cita vs. atención, reprogramaciones, disponibilidad y estados históricos.

2\. Poblar Fact_AtencionCustomer; garantizar que no-shows sin atención no se pierdan.

3\. Diseñar/implementar Fact_SeguimientoTurned y métricas recurrencia según datos disponibles.

4\. Realizar pruebas de reserva concurrente, fechas de atención y duración no negativa.

Entregables comprobables: ETL atención/seguimiento, pruebas agenda, matriz de eventos.

Dependencias y coordinación: Requiere 1 y 2; alimenta dashboard 6.

## 6\. Jeanfranco Jefferson Gonzales Esquivel

Responsabilidad: Visualizaciones BI y experiencia de usuario | Esfuerzo estimado: 20 h | Hito: H4: Analítica y UX

1\. Diseñar tablero ejecutivo con KPI, filtros, drill-through y distinción ingreso vs producción.

2\. Implementar consultas/vistas agregadas para cuadros de buyer, lead, payer, customer, turned.

3\. Revisar el frontend React informado en \[T\], incluir timeline de interacciones si repositorio confirma carencia.

4\. Añadir exportes y estados sin datos; contrastar KPI con conteos SQL del equipo.

Entregables comprobables: Dashboard funcional, capturas, diccionario KPI y consultas asociadas.

Dependencias y coordinación: Empieza prototipos en H2; integra luego de 3–5.

## 7\. Anthony Garcia Ventura

Responsabilidad: Integración backend, seguridad, QA y entrega final | Esfuerzo estimado: 22 h | Hito: H4–H5: Integración y validación

1\. Reproducir en el repositorio cada error reportado por \[T\]: Zod, rutas, notificaciones e índices; crear tickets basados en evidencia.

2\. Implementar correcciones verificadas con tests; revisar acceso RBAC, consentimiento y ausencia de datos clínicos en mart.

3\. Construir pipeline ejecutable, pruebas end-to-end BUYER→TURNED, logs ETL y validación post-commit de mensajes.

4\. Integrar documentación, video demo, reporte de pruebas y procedimiento de despliegue/reversión.

Entregables comprobables: PRs y tests, matriz QA, manual técnico, video y checklist de entrega.

Dependencias y coordinación: Puede iniciar auditoría H1; integración final solo tras 3–6.

# 11\. Secuencia de hitos, puertas de control y colaboración

| Hito                         | Momento relativo | Responsables clave | Condición para continuar                      |
| ---------------------------- | ---------------- | ------------------ | --------------------------------------------- |
| H1 Auditoría y reglas        | Semana 1         | 1 + 7              | Reglas cobro, identity, TURNED y KPI cerradas |
| H2 Esquema y dimensiones     | Semana 2         | 2; soporte 3–5     | Migraciones, dimensiones y claves validadas   |
| H3 Hechos ETL                | Semanas 3–4      | 3, 4 y 5           | 4 hechos poblados; 2a carga sin duplicación   |
| H4 Tablero + UX + QA         | Semana 5         | 6 + 7              | Cuadre BI vs SQL, E2E y control privacidad    |
| H5 Mejora avanzada + entrega | Semana 6         | Todos; coordina 7  | Documentación y demo con evidencia trazable   |

Si el curso dispone de menos tiempo, ejecutar P0 primero: corregir reglas de pago, definir granos, dimensiones, cuatro hechos, conciliación, dashboard base y pruebas. TURNED/finanzas extendidas e IA pasan a P1/P2 según capacidad y existencia de datos.

# 12\. Revisión cruzada y criterios de calidad

| Autor                                  | Revisor                                | Foco        |
| -------------------------------------- | -------------------------------------- | ----------- |
| Germaín Alexander Cruz Vargas          | Marck Alessandro Hermenegildo Pacheco  | reglas      |
| Marck Alessandro Hermenegildo Pacheco  | Mario Antonio Martinez Dominguez       | dimensiones |
| Mario Antonio Martinez Dominguez       | Jesús Daniel Ordóñez Ugarte            | captación   |
| Jesús Daniel Ordóñez Ugarte            | Alexis Gean Gerardo Vigo Huayán        | pagos       |
| Alexis Gean Gerardo Vigo Huayán        | Jeanfranco Jefferson Gonzales Esquivel | atención    |
| Jeanfranco Jefferson Gonzales Esquivel | Anthony Garcia Ventura                 | dashboard   |
| Anthony Garcia Ventura                 | Germaín Alexander Cruz Vargas          | integración |

- Ninguna rama se integra sin SQL reproducible / tests, evidencia de antes-después y revisión cruzada.
- Toda métrica tiene nombre, fórmula, grano, fecha utilizada, filtros, fuente y dueño.
- Todas las operaciones ETL generan BatchId, recuentos insert/update/reject y motivos de rechazo.
- La demostración incluye dos cargas consecutivas, pago cambiado de estado, reserva sin anticipo, reprogramación y paciente recurrente.
- No usar información real de salud en video ni repositorio; utilizar datos sintéticos y enmascarados.

# 13\. Checklist de cierre y carpeta de entrega

☐ 01_analisis/diagnostico_y_reglas.docx + matriz_hallazgos.xlsx (o CSV)

☐ 02_db/ddl_oltp_migraciones.sql + modelo_dimensional.sql + diagramas

☐ 03_etl/01_dimensiones.sql + 02_fact_buyer.sql + 03_fact_lead.sql + 04_fact_payer.sql + 05_fact_customer.sql

☐ 03_etl/06_fact_turned.sql (si viable) + audit_batch.sql + scripts_pruebas.sql

☐ 04_bi/dashboard + definiciones_kpi.md + capturas con resultados conciliados

☐ 05_app/cambios_front_backend + tests + instrucciones de instalación

☐ 06_evidencias/reporte_QA + ejecuciones ETL + video demostración + README general

# 14\. Referencias internas y supuestos

- \[I\] "INforme nexosalud (2).docx": problema, etapas IMPULSE, ER, indicadores y flujo de paciente.
- \[A\] "Anexos Informe NexoSalud.docx": entrevista con sponsor Luxedent, DDL NexoSaludDB y NexoSalud_Mart.
- \[T\] "ANÁLISIS_COMPLETO.md": descripción de stack y lista de incidencias/mejoras reportadas, sin repositorio adjunto.
- \[P\] Recomendaciones técnicas nuevas de este documento: validar su compatibilidad en SQL Server y el repositorio antes de ejecutar migraciones.
- Los plazos son estimaciones de planificación, no fechas dadas por el docente; horas orientativas para equilibrar la carga.