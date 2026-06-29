using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

// Pantalla de detalle de una petición: muestra label + tool + el comando/summary
// COMPLETO (la fila del menú lo trunca a una línea). Ajusta el texto al ancho y
// hace scroll si no cabe. Los datos se le pasan al construirla (los lee el menú de
// Bridge.pending); esta vista NO toca la red. BACK vuelve al menú, donde están
// Aprobar/Denegar.
class RequestDetailView extends WatchUi.View {
    const MARGIN_X     = 30;   // margen lateral (deja sitio a las esquinas redondas)
    const MARGIN_TOP   = 28;
    const HEADER_FONT  = Graphics.FONT_SMALL;
    const BODY_FONT    = Graphics.FONT_TINY;

    var _label;
    var _tool;
    var _summary;
    var _lines   = null;   // summary partido en líneas que caben de ancho
    var _scroll  = 0;      // índice de la primera línea visible del summary
    var _lineH   = 0;
    var _bodyTop = 0;
    var _perPage = 1;

    function initialize(label, tool, summary) {
        View.initialize();
        _label   = (label == null)   ? "" : label;
        _tool    = (tool == null)    ? "" : tool;
        _summary = (summary == null) ? "" : summary;
    }

    // Con el dc disponible, parte el summary y calcula las métricas de scroll.
    function onLayout(dc) {
        var maxW = dc.getWidth() - 2 * MARGIN_X;
        _lines   = wrap(dc, _summary, BODY_FONT, maxW);
        _lineH   = dc.getFontHeight(BODY_FONT);
        if (_lineH <= 0) { _lineH = 1; }   // evita /0 al calcular _perPage
        _bodyTop = MARGIN_TOP + 2 * dc.getFontHeight(HEADER_FONT) + 8;
        var avail = dc.getHeight() - _bodyTop - MARGIN_TOP;
        _perPage = avail / _lineH;
        if (_perPage < 1) { _perPage = 1; }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Cabecera: quién pide (label) y con qué herramienta.
        dc.drawText(MARGIN_X, MARGIN_TOP, HEADER_FONT, _label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(MARGIN_X, MARGIN_TOP + dc.getFontHeight(HEADER_FONT), HEADER_FONT, _tool,
            Graphics.TEXT_JUSTIFY_LEFT);

        // Cuerpo: el summary completo, partido, desde la línea _scroll.
        if (_lines != null) {
            var lines = _lines as Lang.Array;
            var y = _bodyTop;
            var bottom = dc.getHeight() - MARGIN_TOP;
            for (var i = _scroll; i < lines.size() && y < bottom; i++) {
                dc.drawText(MARGIN_X, y, BODY_FONT, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
                y += _lineH;
            }
            // Afordancias de scroll (triángulos, sin depender de glifos de fuente).
            var cx = dc.getWidth() / 2;
            if (_scroll > 0) { triUp(dc, cx, MARGIN_TOP / 2, 6); }
            if (_scroll + _perPage < lines.size()) { triDown(dc, cx, dc.getHeight() - 12, 6); }
        }
    }

    // Scroll con clamp a [0, maxScroll].
    function scrollBy(delta) {
        if (_lines == null) { return; }
        var maxScroll = (_lines as Lang.Array).size() - _perPage;
        if (maxScroll < 0) { maxScroll = 0; }
        _scroll += delta;
        if (_scroll < 0) { _scroll = 0; }
        if (_scroll > maxScroll) { _scroll = maxScroll; }
        WatchUi.requestUpdate();
    }

    // Avanza/retrocede una página dejando una línea de solape como contexto.
    function pageDown() { scrollBy(_perPage > 1 ? _perPage - 1 : 1); }
    function pageUp()   { scrollBy(_perPage > 1 ? -(_perPage - 1) : -1); }

    // Parte "text" en líneas que caben en "maxW" con "font". Rompe por espacios;
    // si una palabra sola no cabe, la trocea por caracteres. Reusa Bridge.splitBy.
    function wrap(dc, text, font, maxW) {
        var lines = [];
        if (text == null || text.equals("")) { return lines; }
        var words = Bridge.splitBy(text, " ");
        var cur = "";
        for (var i = 0; i < words.size(); i++) {
            var w = words[i] as Lang.String;
            var cand = cur.equals("") ? w : (cur + " " + w);
            if (dc.getTextWidthInPixels(cand, font) <= maxW) {
                cur = cand;
            } else {
                if (!cur.equals("")) { lines.add(cur); cur = ""; }
                if (dc.getTextWidthInPixels(w, font) <= maxW) {
                    cur = w;
                } else {
                    // Palabra más ancha que la pantalla: trocéala por caracteres.
                    var chunk = "";
                    var chars = w.toCharArray();
                    for (var j = 0; j < chars.size(); j++) {
                        var c = chars[j].toString();
                        if (dc.getTextWidthInPixels(chunk + c, font) <= maxW) {
                            chunk += c;
                        } else {
                            if (!chunk.equals("")) { lines.add(chunk); chunk = ""; }
                            // Un único carácter más ancho que la pantalla (glifo
                            // Unicode raro): va en su propia línea aunque se recorte,
                            // en vez de arrastrarse en chunk.
                            if (dc.getTextWidthInPixels(c, font) <= maxW) {
                                chunk = c;
                            } else {
                                lines.add(c);
                            }
                        }
                    }
                    cur = chunk;
                }
            }
        }
        if (!cur.equals("")) { lines.add(cur); }
        return lines;
    }

    function triUp(dc, cx, cy, r) {
        dc.fillPolygon([[cx, cy - r], [cx - r, cy + r], [cx + r, cy + r]]);
    }
    function triDown(dc, cx, cy, r) {
        dc.fillPolygon([[cx, cy + r], [cx - r, cy - r], [cx + r, cy - r]]);
    }
}

// Entrada de la pantalla de detalle: scroll con UP/DOWN o swipe; BACK vuelve al menú.
class RequestDetailDelegate extends WatchUi.BehaviorDelegate {
    var _view;
    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }
    function onNextPage()     { _view.pageDown(); return true; }
    function onPreviousPage() { _view.pageUp();   return true; }
    function onBack()         { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}
