import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.ActivityMonitor;

// Esfera dotmesh — dirección "Prompt/terminal": la esfera es tu shell, en columna
// alineada a la izquierda como una sesión de terminal:
//
//   # sáb 27                       ← fecha como comentario de código (gris)
//   ▌batería ▶ pasos ▶ notif ▶     ← el prompt: powerline (borde izq recto, pico dcho)
//   ❯ 15:15 ▏                      ← la hora como input que se escribe
//
// Monocromo primero; el color es señal: peach = batería, azul = pasos, violeta
// (lilac) = notificaciones cuando las hay (gris si no), teal = el cursor (lo vivo),
// sage = el chevron, rose = batería baja. La powerline usa la rampa chrome de grafito.
class DotmeshWatchView extends WatchUi.WatchFace {

    private var _lowPower as Boolean = false;
    private var _timeFont = null;   // JetBrains Mono SemiBold (hora, input)
    private var _smallFont = null;  // JetBrains Mono Medium (powerline/comentario)
    private var _iconFont = null;   // iconos (batería, pasos, campana)

    // Iconos: PUA del BMP asignada por scripts/gen-iconfont.py.
    private const ICON_BELL  = 0xE000;
    private const ICON_BATT  = [0xE001, 0xE002, 0xE003, 0xE004, 0xE005]; // vacía→llena
    private const ICON_STEPS = 0xE006;

    // Castellano fijo: la esfera no sigue el idioma del sistema.
    private const DOW = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];

    // Geometría (espacio de 416 px) — columna alineada a la izquierda.
    private const LX = 40;            // margen izquierdo de la columna
    private const TIP = 12;           // pico (costura) de los segmentos
    private const PW_H = 52;          // alto de la powerline
    private const PW_TARGET_BODY = 348; // ancho del cuerpo: estira hasta ~x400 (pico)
    private const COMMENT_CY = 138;   // comentario de fecha
    private const PW_CY = 182;        // centro de la powerline
    private const PROMPT_CY = 252;    // centro de la hora (input)
    private const AOD_COMMENT_CY = 172;
    private const AOD_PROMPT_CY = 224;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _timeFont = WatchUi.loadResource(Rez.Fonts.TimeFont);
        _smallFont = WatchUi.loadResource(Rez.Fonts.SmallFont);
        _iconFont = WatchUi.loadResource(Rez.Fonts.IconFont);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (_lowPower) {
            drawAmbient(dc);
        } else {
            drawActive(dc);
        }
    }

    // ===================== Modo activo (alta potencia) ======================
    // onUpdate corre 1×/s en alta potencia: la hora y el parpadeo del cursor
    // van en vivo aquí.
    private function drawActive(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        drawComment(dc, COMMENT_CY, info, Palette.TEXT_DIM);
        drawPowerline(dc);
        drawPrompt(dc, PROMPT_CY, System.getClockTime(), true);
    }

    // ===================== Always-on (baja potencia) ========================
    // Negro puro, todo atenuado: comentario + input. Sin powerline.
    private function drawAmbient(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        drawComment(dc, AOD_COMMENT_CY, info, Palette.AOD_DATE);
        drawPrompt(dc, AOD_PROMPT_CY, System.getClockTime(), false);
    }

    // =========================== Piezas de dibujo ===========================

    // Fecha como comentario de shell: "# sáb 27" (alineado a la izquierda).
    private function drawComment(dc as Graphics.Dc, cy as Number, info, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(LX, cy, _smallFont, "# " + dateShort(info),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Línea de input: ❯ (chevron) HH:MM (hora) ▏(cursor), alineada a la izquierda.
    // En activo: chevron sage, hora blanca, cursor teal parpadeante. En AOD: atenuado
    // y el cursor fijo.
    private function drawPrompt(dc as Graphics.Dc, cy as Number, clock, live as Boolean) as Void {
        var hh = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hh = hh % 12;
            if (hh == 0) { hh = 12; }
        }
        var hhmm = hh.format("%02d") + ":" + clock.min.format("%02d");

        // Chevron ❯ (dos trazos) en el margen.
        var cw = 16;
        var ch = live ? 24 : 20;
        dc.setColor(live ? Palette.SAGE : Palette.AOD_CHEV, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(live ? 6 : 4);
        dc.drawLine(LX, cy - ch, LX + cw, cy);
        dc.drawLine(LX + cw, cy, LX, cy + ch);
        dc.setPenWidth(1);

        var x = LX + cw + 12;
        dc.setColor(live ? Graphics.COLOR_WHITE : Palette.AOD_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, _timeFont, hhmm,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += dc.getTextWidthInPixels(hhmm, _timeFont) + 8;

        // Cursor: parpadea en activo (1×/s); fijo y atenuado en AOD.
        if (live) {
            if (clock.sec % 2 == 0) {
                dc.setColor(Palette.TEAL, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, cy - 28, 8, 56);
            }
        } else {
            dc.setColor(Palette.AOD_CURSOR, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, cy - 23, 7, 46);
        }
    }

    // El prompt: powerline starship con 3 segmentos fijos (batería · pasos · notif),
    // borde izquierdo recto y pico a la derecha (y costura en pico entre segmentos).
    private function drawPowerline(dc as Graphics.Dc) as Void {
        var ds = System.getDeviceSettings();
        var pct = System.getSystemStats().battery.toNumber();
        var low = pct <= 15;
        var notif = ds.notificationCount;

        var segs = [];
        // batería — peach (rose si baja, como señal de error).
        segs.add({
            :icon => batteryGlyph(pct), :ic => (low ? Palette.ROSE : Palette.PEACH),
            :text => pct.format("%d") + "%", :tc => (low ? Palette.ROSE : Palette.PEACH),
            :bg => Palette.CHROME_2
        });
        // pasos — azul.
        var am = ActivityMonitor.getInfo();
        var steps = (am != null && am.steps != null) ? am.steps : 0;
        segs.add({
            :icon => ICON_STEPS, :ic => Palette.BLUE,
            :text => stepsK(steps), :tc => Palette.BLUE, :bg => Palette.CHROME_3
        });
        // notif — violeta (lilac) si hay, gris atenuado si 0.
        var nic = (notif > 0) ? Palette.LILAC : Palette.TEXT_2;
        segs.add({
            :icon => ICON_BELL, :ic => nic,
            :text => notif.format("%d"), :tc => nic, :bg => Palette.CHROME_4
        });

        var n = segs.size();
        var widths = new [n];
        var lpads = new [n];
        for (var i = 0; i < n; i += 1) {
            var lp = (i == 0) ? 14 : (TIP + 7);   // primer segmento: borde recto
            lpads[i] = lp;
            widths[i] = lp
                + dc.getTextWidthInPixels(segs[i][:icon].toChar().toString(), _iconFont) + 6
                + dc.getTextWidthInPixels(segs[i][:text], _smallFont) + 12;
        }
        // Estirar hasta PW_TARGET_BODY para que casi llegue al borde derecho: el
        // hueco sobrante se reparte como padding derecho entre los segmentos.
        var content = 0;
        for (var i = 0; i < n; i += 1) { content += widths[i]; }
        var extra = PW_TARGET_BODY - content;
        if (extra > 0) {
            var per = extra / n;
            for (var i = 0; i < n; i += 1) { widths[i] += per; }
            widths[n - 1] += extra - per * n;   // resto al último
        }
        var top = PW_CY - PW_H / 2;
        var bot = PW_CY + PW_H / 2;
        var xs = new [n];
        var bx = LX;
        for (var i = 0; i < n; i += 1) { xs[i] = bx; bx += widths[i]; }

        // 1) Cuerpos (borde izquierdo recto; rectángulos abutidos).
        for (var i = 0; i < n; i += 1) {
            dc.setColor(segs[i][:bg], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(xs[i], top, widths[i], PW_H);
        }
        // 2) Pico tras CADA segmento (los internos son costura; el último, el pico
        //    derecho del prompt).
        for (var i = 0; i < n; i += 1) {
            var seam = xs[i] + widths[i];
            dc.setColor(segs[i][:bg], Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[seam, top], [seam + TIP, PW_CY], [seam, bot]]);
        }
        // 3) Contenido (icono + texto), libre de la costura entrante.
        for (var i = 0; i < n; i += 1) {
            var s = segs[i];
            var glyph = s[:icon].toChar().toString();
            var ix = xs[i] + lpads[i];
            dc.setColor(s[:ic], Graphics.COLOR_TRANSPARENT);
            dc.drawText(ix, PW_CY, _iconFont, glyph,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            ix += dc.getTextWidthInPixels(glyph, _iconFont) + 6;
            dc.setColor(s[:tc], Graphics.COLOR_TRANSPARENT);
            dc.drawText(ix, PW_CY, _smallFont, s[:text],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // =============================== Datos ==================================

    // Fecha corta de shell: "sáb 27" (día de semana + día del mes, sin cero).
    private function dateShort(info) as String {
        return DOW[(info.day_of_week - 1) % 7] + " " + info.day.format("%d");
    }

    // Pasos compactos: 8400 → "8.4k", 12000 → "12k", 540 → "540".
    private function stepsK(steps as Number) as String {
        if (steps >= 1000) {
            var whole = steps / 1000;
            var frac = (steps % 1000) / 100;
            if (frac == 0) {
                return whole.format("%d") + "k";
            }
            return whole.format("%d") + "." + frac.format("%d") + "k";
        }
        return steps.format("%d");
    }

    // Glifo de batería según el nivel (vacía → llena).
    private function batteryGlyph(pct as Number) as Number {
        var idx = pct / 25;            // 0..4
        if (idx > 4) { idx = 4; }
        if (idx < 0) { idx = 0; }
        return ICON_BATT[idx];
    }

    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }
}
