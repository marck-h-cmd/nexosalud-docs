# Análisis Completo del Proyecto: Metodología IMPULSE

## 1. Visión General del Proyecto

Este es un sistema de inteligencia de negocios para una clínica odontológica (NexoSalud) que gestiona el ciclo de vida del paciente desde el contacto inicial hasta convertirse en cliente fijo (PAYER/CUSTOMER). El proyecto utiliza una arquitectura full-stack con:

- **Frontend**: React + TypeScript + Vite + TanStack Query
- **Backend**: Node.js + Express + Prisma ORM + SQL Server
- **Base de Datos**: SQL Server con modelo relacional completo

### Flujo Actual del Paciente
BUYER → LEAD → RESERVA → PAYER → CUSTOMER → TURNED (paciente perdido)

## 2. Errores Detectados y Soluciones

### 2.1 Backend - Lógica de Duplicados Inconsistente

**Error**: El endpoint `check-duplicate` en `buyer.routes.ts` verifica duplicados pero no considera correctamente el canal y fuente de atracción, lo que puede crear registros duplicados intencionales para diferentes segmentos.

**Solución**: Mejorar la lógica de detección para que considere la combinación de (teléfono + canal + fuente) antes de marcar como duplicado, permitiendo que el mismo contacto pueda tener diferentes intenciones de consulta.

### 2.2 Backend - Faltante de Validación en `register` Buyer

**Error**: En la ruta `/register` del buyer, el campo `isNewPersonConfirmed` se usa pero no está definido en el `buyerSchema.ts`, lo que permite enviar datos incompletos.

**Solución**: Añadir validación Zod para `isNewPersonConfirmed` en `buyerSchema.ts` y asegurar que el flujo de conversión a LEAD sea consistente.

### 2.3 Backend - Endpoint de Pre-Reserva Pública Faltante de Envío de Notificaciones

**Error**: La ruta `/public/:id/pre-reserve` en `lead.routes.ts` completa la reserva pero no dispara automáticamente las notificaciones de correo o WhatsApp al paciente.

**Solución**: Integrar llamada al `NegotiatorAgentService.processAndDispatch()` después de crear la reserva para enviar automáticamente el flyer y las notificaciones.

### 2.4 Frontend - Faltante de Campos en Formulario de Lead

**Error**: El `leadUpdateSchema` en `leadSchema.ts` tiene campos limitados (`receptionDate`, `firstResponseDate`, etc.) pero falta la integración con preferencias del paciente para ofertas personalizadas.

**Solución**: Extender el schema para incluir `preferredChannels`, `preferredSedes`, `preferredProfessionals` y `lastContactMethod`.

### 2.5 Base de Datos - Relaciones No Optimizadas para Reportes

**Error**: El modelo `EventosEtapa` no tiene índices optimizados para consultas de trayectoria de paciente, lo que afecta los reportes de conversión.

**Solución**: Añadiríndices compuestos en `EventosEtapa` para `(id_persona, fecha_hora)` y `(etapa_destino, fecha_hora)` para reportes rápidos.

### 2.6 Backend - Falta de Integración WhatsApp en el Servicio de Negociación

**Error**: El `NegotiatorAgentService` tiene soporte para envío de correo pero la generación de mensaje WhatsApp es estática y no usa datos reales del paciente desde la BD.

**Solución**: Mejorar la construcción del mensaje WhatsApp para que incluya datos reales desde la base de datos (historial, preferencias, última consulta).

### 2.7 Frontend - No hay componente de historial de contacto visible

**Error**: Los componentes de ` buyer-page.tsx` y `lead-page.tsx` no muestran el historial de interacciones en un formato fácil de escanear para el agente comercial.

**Solución**: Crear un componente `InteractionHistory` que muestre las últimas 5 interacciones con canales, fechas y tipos.

## 3. Mejoras para la Metodología "IMPULSE"

La metodología "IMPULSE" se enfoca en **Atracción, Conversión y Retención** de clientes. Aquí las propuestas detalladas:

### 3.1 Atracción de Nuevos Clientes

#### 3.1.1 Web Forms Optimizados con Captación de Datos Preferenciales

**Problema Actual**: El formulario `NewBuyerPage.tsx` y `BuyerRequestInfoPage.tsx` capturan información básica pero no aprovechan datos de segmentación para campañas futuras.

**Mejora Propuesta**:
- Añadir campos de segmentación inteligente en el formulario de registro:
  - `origen_publicidad` (Meta Ads, Google Ads, Referido, Espontáneo)
  - `interes_principal` (Ortodoncia, Implantes, Blanqueamiento, Limpieza)
  - `presupuesto_referencia`
  - `autorizacion_mkt` (para recibir promociones exclusivas)

- Implementar **progressive profiling**: En cada retorno del cliente, preguntar solo por datos nuevos en lugar de todo el formulario nuevamente.

```typescript
// Ejemplo de mejora en buyerSchema.ts
contactAuthorization: z.boolean().refine((val) => val === true, {
  message: 'Autorización requerida para enviar ofertas personalizadas',
}).optional(),
```

#### 3.1.2 Integración de WhatsApp Empresarial

**Problema Actual**: El sistema menciona canales de WhatsApp pero no tiene integración activa con la API de WhatsApp Business para envío proactivo de mensajes.

**Mejora Propuesta**:
1. Configurar WhatsApp Business API (o proveedor como Twilio, WATI, Meta Business API)
2. Implementar webhook para recibir respuestas automáticas
3. Crear flujo de mensajes automatizados:

```
Ejemplo de secuencia de WhatsApp:
1. Mensaje de bienvenida al registrarse: "¡Hola! 👋 Gracias por interesarte en NexoSalud. Responde 'INFO' para recibir nuestra guía de primera visita."
2. 24h después: "Hola [nombre], vimos que aún no hemos agendado tu evaluación. ¿Te parece si te enviamos horarios disponibles?"
3. Después de 3 días sin respuesta: Mensaje de reenganche con oferta especial
```

#### 3.1.3 Alertas de Correo Electrónico Automatizadas

**Problema Actual**: El servicio `NegotiatorAgentService.sendSimulationOfferEmail` existe pero requiere activación manual y no se dispara automáticamente después de ciertas acciones.

**Mejora Propuesta**:
- Automatizar el envío de correos en estos triggerpoints:
  - Cuando un BUYER pasa a LEAD → enviar correo de bienvenida + oferta inicial
  - Cuando un LEAD selecciona una alternativa → enviar recordatorio de reserva
  - Cuando un PAYER realiza primer pago → enviar correo de agradecimiento + sugerencia de servicio complementario
  - Cumpleaños del paciente (usando `fecha_nacimiento` del modelo Personas)

```typescript
// Ejemplo de trigger automático en buyer.routes.ts después de convertir a LEAD
await sendWelcomeEmail(persona.id_persona, leadData);
```

### 3.2 Uso de Información de Preferencias y Gustos

#### 3.2.1 Personalización Oferta Basada en Historial

**Problema Actual**: El sistema tiene `personaPreferencias` pero no se usa para personalizar las ofertas comerciales en tiempo real.

**Mejora Propuesta**:
- Al generar el flyer Canva o el correo, consultar las preferencias almacenadas:
  - `sede_preferida` → seleccionar sede automáticamente
  - `profesional_preferido` → sugerir profesionales similares
  - `id_modalidad` → ofrecer solo horarios de la modalidad preferida
  - `id_canal` → preferir contacto por el canal historico

**Implementación en `NegotiatorAgentService.processAndDispatch`**:
```typescript
// Consultar preferencias antes de generar la oferta
const preferencias = await prisma.personaPreferencias.findFirst({
  where: { id_persona: params.leadId },
  include: { Canal: true, Modalidad: true, ServicioInteres: true }
});

// Aplicar preferencias a los parámetros
const serviceName = preferencias.ServicioInteres?.nombre || params.serviceName;
const sedeName = preferencias.sede_preferida || 'Sede Default';
```

#### 3.2.2 Segmentación Inteligente para Campañas

**Propuesta**: Crear un endpoint `/api/buyers/segment` que agrupe pacientes por:
- Servicios de interés
- Sedes preferidas
- Ultima visita odontológica
- Autorización de contacto
- Campaña de origen

Esto permite enviar ofertas segmentadas en lugar de masivas.

### 3.3 Automatización y IA

#### 3.3.1 Agente de Negociación Automático

**Problema Actual**: `NegotiatorAgentService` tiene lógica compleja pero no está integrado al flujo automático de leads.

**Mejora Propuesta**:
1. Crear endpoint `/api/negotiator/auto-reserve` que, cuando un lead no responde en 48h, el agente:
   - Consulta preferencias y horario disponible
   - Envía propuesta automática por WhatsApp/correo
   - Si no hay respuesta en 24h, nueva propuesta con mejor descuento
   - Después de 7 días, marcar como "Lost" pero mantener en nurturing

#### 3.3.2 Scoring de Lead (Lead Scoring)

**Propuesta Implementar**:
- Asignar puntaje basado en:
  - ✅ Completo de formulario (0-20 pts)
  - ✅ Autorización de contacto (0-15 pts)
  - ✅ Interés en servicio de alto valor (0-25 pts)
  - ✅ Frecuencia de visitas/web (0-20 pts)
  - ✅ Coincidencia de presupuesto (0-20 pts)
- Umbral: >70 pts → Prioritario para agente humano; <30 → Flujo automático de nurturing

## 4. Propuestas de Implementación por Capa

### 4.1 Capa Frontend

**Archivos a modificar/crear**:

1. **`src/components/InteractionHistory.tsx`** - Nuevo componente para mostrar historial de interacciones en tarjetas compactas con iconos de canal y fechas.

2. **`src/modules/lead/pages/LeadDetailPage.tsx`** - Mejorar para mostrar:
   - Historial de interacciones
   - Score de lead
   - Preferencias almacenadas
   - Próximos pasos sugeridos por IA

3. **`src/modules/buyer/pages/NewBuyerPage.tsx`** - Añadir:
   - Checkbox "Autorizar envío de ofertas personalizadas"
   - Selector de origen de atracción con íconos
   - Preferencias iniciales (sede, horario, profesional)

4. **`src/modules/buyer/pages/BuyerPage.tsx`** - Añadir vista de:
   - Segmentación de pacientes
   - Indicadores de nuturing
   - Acciones rápidas de contacto

5. **`src/shared/hooks/useLeadScoring.ts`** - Nuevo hook para calcular score de lead en cliente:
   ```typescript
   export function useLeadScoring(id: string) {
     const { data, isLoading } = useQuery({
       queryKey: ['lead-scoring', id],
       queryFn: () => leadService.getLeadDetails(id),
     });
     
     return {
       score: calculateScore(data),
       category: getCategory(data),
       recommendedActions: getRecommendedActions(data),
     };
   }
   ```

6. **`src/components/NotificationCenter.tsx`** - Centro de notificaciones para el agente con:
   - Alertas de nuevos leads
   - Recordatorios de seguimiento
   - Mensajes nuevos de WhatsApp/correo

### 4.2 Capa Backend

**Endpoints a agregar/modificar**:

1. **`POST /api/buyers/:id/preferences`** - Actualizar preferencias completas del paciente.

2. **`POST /api/leads/:id/auto-nurture`** - Activar nuturing automático para lead inactivo.

3. **`GET /api/buyers/segment`** - Endpoint de segmentación para campañas.

4. **`POST /api/negotiator/dispatch-auto`** - Despacho automático de ofertas basado en triggers.

5. **`GET /api/catalogs/complete`** - Catálogos completos con datos enriquecidos para el formulario.

**Mejoras en servicios existentes**:

- **`negotiatorAgentService.ts`**: Añadir método `autoGenerateAndDispatch` que:
  - Consulta preferencias del paciente
  - Genera oferta personalizada
  - Envía WhatsApp + correo en una sola operación
  - Programa seguimiento automático

- **`buyer.service.ts`**: Añadir método `registerWithEnrichment` que capture datos adicionales en el momento del registro.

- **`lead.service.ts`**: Añadir método `convertToPayerWithNotifications` que dispare comunicaciones automáticas.

### 4.3 Capa Base de Datos

**Procedimientos almacenados recomendados**:

1. **`sp_update_patient_preferences`** - Actualizar todas las preferencias en una sola transacción.

2. **`sp_calculate_lead_score`** - Calcular score basado en historial completo.

3. **`sp_get_patient_journey` - Obtener trayectoria completa del paciente desde BUYER hasta hoy.

4. **`sp_send_patient_birthday_alert`** - Alertar sobre próximos cumpleaños para envío de oferta.

**Indices recomendados**:

```sql
-- Índice compuesto para consultas de trayectoria
CREATE INDEX idx_eventosetapa_persona_fecha ON EventosEtapa(id_persona, fecha_hora DESC);

-- Índice para búsquedas de duplicados por teléfono
CREATE INDEX idx_personas_numero_ultimo ON Personas(numero(9));

-- Índice para reportes de conversión por etapa
CREATE INDEX idx_solicitudes_estado_fecha ON Solicitudes(estado, fecha_solicitud DESC);
```

**Datos semilla faltantes** (ver `database/seed/`):
- Añadir datos de campañas de marketing reales
- Datos de gastos de campaña por fuente/canal
- Historial de interacciones iniciales

## 5. Roadmap de Implementación

### Fase 1 - Fundamentos (Sprint 1-2)
- [ ] Corregir validaciones en buyerSchema.ts (añadir isNewPersonConfirmed)
- [ ] Mejorar lógica de duplicados en buyer.routes.ts
- [ ] Crear componente InteractionHistory para frontend
- [ ] Añadir campos de preferencia en formulario NewBuyerPage

### Fase 2 - Atracción y Nurturing (Sprint 3-4)
- [ ] Implementar WhatsApp Business API integration
- [ ] Crear endpoint /api/buyers/segment
- [ ] Implementar lead scoring en useLeadScoring.ts
- [ ] Automatizar envío de correo en triggers key

### Fase 3 - Personalización IA (Sprint 5-6)
- [ ] Mejorar NegotiatorAgentService con auto-dispatch
- [ ] Implementar preferencias dinámicas en ofertas Canva/correo
- [ ] Crear agente de seguimiento automático para leads inactivos
- [ ] Añadir segmentación por comportamiento en reportes

### Fase 4 - Optimización y Reportes (Sprint 7-8)
- [ ] Optimizar índices en BD para reportes
- [ ] Crear dashboard de indicadores IMPULSE (tasa de conversión, costo por adquisición, LTV)
- [ ] Implementar cumplannas reminders automáticos
- [ ] Revisar y refactorizar todo el flujo BUYER→LEAD→PAYER

## 6. Conclusión

El proyecto tiene una base sólida con una arquitectura bien definida y un modelo de datos completo. Los puntos críticos para implementar la metodología "IMPULSE" giran en torno a:

1. **Datos completos en el registro** - Capturar preferencias y autorizaciones desde el inicio
2. **Integración omnicanal** - WhatsApp + Correo + Portal Web sincronizados
3. **Automatización inteligente** - Disparos basados en comportamiento, no solo manuales
4. **Personalización verdadera** - Usar las preferencias almacenadas para cada oferta

Los errores detectados son principalmente de consistencia y completitud de datos, no de funcionalidad crítica. Las mejoras propuestas mejorarán significativamente la tasa de conversión BUYER→LEAD→PAYER y crearán un sistema de nurturing efectivo para maximizar el valor de cada nuevo cliente atraído.