import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Esfera dotmesh — dirección "Terminal/prompt".
// Cuatro datos: fecha (comentario), hora (peach), batería y notificaciones.
// Monocromo primero; color solo como señal: peach = la hora (identidad),
// sage = notificaciones, rose = batería baja.
class DotmeshWatchView extends WatchUi.WatchFace {

    private var _lowPower as Boolean = false;
    private var _width as Number = 416;
    private var _height as Number = 416;
    private var _timeFont = null;   // JetBrains Mono grande (hora)
    private var _smallFont = null;  // JetBrains Mono pequeña (resto)
    private var _iconFont = null;   // campana (Nerd Font)

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _width = dc.getWidth();
        _height = dc.getHeight();
        _timeFont = WatchUi.loadResource(Rez.Fonts.TimeFont);
        _smallFont = WatchUi.loadResource(Rez.Fonts.SmallFont);
        _iconFont = WatchUi.loadResource(Rez.Fonts.IconFont);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var cx = _width / 2;
        var cy = _height / 2;
        var clock = System.getClockTime();

        var bg = _lowPower ? Palette.AOD_BG : Palette.INK_0;
        dc.setColor(Graphics.COLOR_WHITE, bg);
        dc.clear();

        drawDateComment(dc, cx, cy - 120, clock);
        drawTime(dc, cx, cy, clock);
        if (!_lowPower) {
            drawBottomRow(dc, cx, cy + 124);
        }
    }

    // // sáb 27 jun  — fecha como comentario (gris atenuado), castellano fijo.
    private function drawDateComment(dc, cx, y, clock) {
        var dow = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
        var mon = ["ene", "feb", "mar", "abr", "may", "jun",
                   "jul", "ago", "sep", "oct", "nov", "dic"];
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = Lang.format("// $1$ $2$ $3$", [
            dow[(info.day_of_week - 1) % 7],
            info.day.format("%d"),
            mon[(info.month - 1) % 12]
        ]);
        dc.setColor(Palette.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, _smallFont, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // HH:MM en peach; los dos puntos también peach (parte de la cifra).
    private function drawTime(dc, cx, cy, clock) {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var gap = 20;
        dc.setColor(Palette.PEACH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - gap, cy, _timeFont, hour.format("%02d"),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + gap, cy, _timeFont, clock.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.fillCircle(cx, cy - 22, 6);
        dc.fillCircle(cx, cy + 22, 6);
    }

    // Fila inferior: ❯ batería · campana(contador).
    // Batería en Paper (rose si baja); campana sage con contador si hay avisos,
    // gris en contorno si no. notificationCount es el dato real del móvil — el
    // mismo que sube cuando bridge empuja un aviso de Claude.
    private function drawBottomRow(dc, cx, y) {
        var notif = System.getDeviceSettings().notificationCount;
        var pct = System.getSystemStats().battery.toNumber();
        var batText = pct.format("%d") + "%";
        var batColor = pct <= 15 ? Palette.ROSE : Palette.PAPER;

        var bell = glyph(notif > 0 ? 0xF0F3 : 0xF0A2);
        var bellColor = notif > 0 ? Palette.SAGE : Palette.TEXT_DIM;
        var countText = notif > 0 ? notif.format("%d") : "";

        var wBat = dc.getTextWidthInPixels(batText, _smallFont);
        var wBell = dc.getTextWidthInPixels(bell, _iconFont);
        var wCount = countText.equals("") ? 0 : dc.getTextWidthInPixels(countText, _smallFont);
        var chevW = 16;
        var gapA = 16;   // chevron → batería
        var gapB = 26;   // batería → campana
        var gapC = 5;    // campana → contador
        var total = chevW + gapA + wBat + gapB + wBell + (wCount > 0 ? gapC + wCount : 0);
        var x = cx - total / 2;

        // chevron ❯ como estructura (gris)
        dc.setColor(Palette.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x, y - 7, x + 9, y);
        dc.drawLine(x + 9, y, x, y + 7);
        dc.setPenWidth(1);
        x += chevW + gapA;

        // batería
        dc.setColor(batColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _smallFont, batText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += wBat + gapB;

        // campana + contador
        dc.setColor(bellColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _iconFont, bell,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += wBell;
        if (wCount > 0) {
            x += gapC;
            dc.drawText(x, y, _smallFont, countText,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Codepoint → String de un solo glifo.
    private function glyph(code) {
        return code.toChar().toString();
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
