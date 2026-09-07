# BBW CONTROL FINANCIERO
Sistema P&L · Big Bang Workshops · Panamá

---

## PUBLICAR (una sola vez)

1. Creá un repo en GitHub — por ejemplo `bbw-finanzas`. **Ponelo privado si querés**,
   GitHub Pages igual funciona en repos privados con cuenta Pro; si es cuenta free,
   tiene que ser público. No pasa nada: el archivo no contiene secretos, y sin
   usuario y contraseña no se ve ni un número.
2. Subí `index.html` a la raíz del repo.
3. Settings → Pages → Source: `Deploy from a branch` → rama `main`, carpeta `/ (root)`.
4. A los dos minutos tenés el link: `https://TUUSUARIO.github.io/bbw-finanzas/`
5. Ese link se lo pasás al equipo. En el celular: abrir → menú → **Agregar a
   pantalla de inicio**. Queda como una app.

---

## PRIMER ARRANQUE

**El primer usuario que se registre queda ADMIN automáticamente.** Registrate vos
primero, antes de pasarle el link a nadie. Después el resto entra como staff.

---

## PERMISOS

Dos roles. **Admin** ve y hace todo. **Staff** arranca sin ningún permiso y vos le
vas prendiendo lo que necesite, uno por uno, desde la pestaña **Equipo**.

| Switch | Prendido | Apagado |
|---|---|---|
| Ve los movimientos de todos | Ve lo que carga todo el taller | Solo ve lo que él mismo registró |
| Ve costos y gastos | Registra y ve compras a proveedor y gastos | Solo ventas: ni siquiera aparecen las cuentas de costo |
| Ve el estado de resultados | Ve el P&L, márgenes y utilidad neta | No le aparece la pestaña |
| Cuenta activa | Entra normal | No entra ni ve nada — para quien deja el taller |

Un staff nuevo entra viendo solo las ventas que él mismo carga. Nada más.

### Esto está en la base, no en la pantalla

Los permisos son políticas de Row Level Security en Postgres. Si alguien abre la
consola del navegador o llama la API directo, la base simplemente no le devuelve
las filas. Verificado antes de entregar con cuatro usuarios reales: un staff sin
permisos intentó registrar un gasto, ascenderse a admin por UPDATE directo y
llamar la función de administración. Las tres cosas rebotaron.

### Lo único que NO es un muro

**"Ve el estado de resultados" es cosmético si la persona también tiene "ve los
movimientos de todos".** Con todos los movimientos a la vista, cualquiera suma y
saca la rentabilidad, tenga o no la pestaña.

Si querés que alguien de verdad no sepa cuánto gana el taller, dejale **apagado
"ve los movimientos de todos"**. Ahí solo ve lo suyo y no tiene con qué calcular.

### Candados

- No podés quitarte a vos mismo el admin ni darte de baja.
- El sistema no te deja quedarte sin ningún admin activo.
- Un staff puede borrar lo suyo dentro de las primeras 24 horas — para que arregle
  un tipeo del día sin poder tocar el mes cerrado. Después, solo un admin.

## PLANES MENSUALES

Suscripciones y cargos fijos: Adobe, hosting, alquiler, lo que se cobre solo
todos los meses. Se cargan **una vez** desde la pestaña Planes y el gasto
aparece cada mes sin que nadie lo escriba.

Al agregar un plan indicás nombre, monto, categoría, día de cobro y el primer
mes que se cobró. En ese momento se generan de una vez los cargos de todos los
meses desde ese primer mes hasta hoy, y de ahí en adelante cada mes se suma
solo al entrar. **Nunca adelanta meses futuros.**

En la lista de movimientos estos cargos llevan la etiqueta **AUTO**.

### Cancelar

`Cancelar` marca el último mes cobrado (el mes en curso) y corta desde el
siguiente. Lo ya cobrado queda intacto — el historial no se toca nunca. Un plan
cancelado se puede reactivar; solo se puede borrar de verdad si nunca generó
un cargo, para no dejar movimientos huérfanos.

### La carga fija mensual

Arriba de la pestaña se ve el total de los planes activos, y el mismo número
anualizado. Es el piso que el taller tiene que cubrir todos los meses antes de
ganar un peso — el número que conviene comparar contra el margen bruto.

### Detalles que ya están resueltos

- **No duplica.** Una bitácora aparte registra qué mes se generó para qué plan.
  Correr el devengo diez veces genera lo mismo que correrlo una.
- **Borrar un cargo no lo resucita.** Si eliminás el movimiento de un mes que
  no se llegó a cobrar, no vuelve a aparecer.
- **Día 31 en un mes corto** cae en el último día del mes, no se pierde.
- **Solo admin.** Los planes son estructura de costos: un staff no los ve ni
  puede ejecutar el devengo, ni siquiera llamando la API directo.

---

## CERRAR EL REGISTRO (hacelo cuando el equipo ya esté adentro)

Mientras el registro esté abierto, cualquiera con el link puede crearse una cuenta.
No vería datos ajenos, pero ensucia la lista. Cuando ya estén todos:

Supabase → Authentication → Sign In / Providers → Email → apagá **Allow new users to sign up**

Después, para sumar a alguien: Authentication → Users → Add user.

**Confirmación por correo:** viene prendida. Si a tu equipo le complica, se apaga en
Authentication → Sign In / Providers → Email → *Confirm email*. Bajás fricción y
bajás seguridad — decisión tuya.

---

## ESTRUCTURA DEL P&L

    Ingresos
      DTF personalizado · Sublimación · Toppers · Diseño · Otros
    − Costo directo (COGS)
      Transfers DTF/UV · Prendas en blanco · Insumos · Maquila
    = MARGEN BRUTO          ← valida el precio mayorista
    − Gastos operativos (OpEx)
      Nómina · Alquiler y servicios · Software · Marketing
      Transporte · Equipo · Otros
    = UTILIDAD NETA

Para agregar o cambiar cuentas: Supabase → Table Editor → `cuentas`. El campo
`grupo` (`ingreso` / `costo` / `opex`) es el que decide dónde cae en el P&L —
no el tipo que elegís en el formulario.

---

## BASE DE DATOS

Proyecto Supabase: **bigbangworkshops** (`cglankaljvhcdyzhyooo`)

| Tabla | Qué guarda |
|---|---|
| `perfiles` | Nombre, correo, rol, activo y los tres permisos |
| `cuentas` | Plan de cuentas |
| `movimientos` | Un registro por ingreso o egreso |
| `suscripciones` | Los planes mensuales. `mes_fin` null = vigente |
| `suscripciones_generadas` | Bitácora de devengo: qué mes ya se generó |
| `v_movimientos` | Vista de lectura con nombre de cuenta, grupo y quién registró |

La administración de miembros pasa por la función `admin_guardar_miembro`, que
verifica que quien llama sea admin antes de tocar nada. No se edita `perfiles`
directo: el permiso a nivel de columna solo deja cambiar el propio nombre.

Los proyectos free de Supabase **se pausan tras una semana sin uso**. Si un lunes
nadie puede entrar, es eso: entrá al panel de Supabase y dale *Restore*. Si el
sistema se usa a diario no pasa.

---

## MARCA

Negro `#111111` · Amarillo `#FFC629` · Bebas Neue / Montserrat / Inter.
Etiquetas "rule" en Inter, 11px, tracking `0.28em`.

Un solo color fuera de paleta: `#E0574F`, usado **únicamente** cuando la utilidad
neta da negativa. Ingreso y egreso se distinguen por forma (franja amarilla vs.
gris, signo), no por color nuevo. Pendiente de ratificar en Governance 09.

---

## PENDIENTES

- [ ] Comparativo mes contra mes
- [ ] Enlazar cuentas de costo con el doc 11 de costos de proveedor
- [ ] Cierre de mes bloqueado (que no se editen meses ya cerrados)
- [ ] Historial de cambios de permisos (quién le dio qué acceso a quién)
- [ ] Aviso cuando un plan sube de precio
- [ ] Planes anuales y trimestrales (hoy solo mensuales)
