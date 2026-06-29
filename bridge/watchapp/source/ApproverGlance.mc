using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;
using Toybox.Lang;

// Tarjeta glance del approver: muestra la última petición pendiente (que el menú
// guarda en Application.Storage como ["label","tool","summary"]) sin abrir la app.
// Al tocar la glance, el sistema abre la app y su menú. Corre con memoria limitada
// (32 KB), así que solo lee Storage y pinta; nada de red ni de cargar el menú.
(:glance)
class ApproverGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var h = dc.getHeight();

        var pending = Application.Storage.getValue("lastPending");
        if (!(pending instanceof Lang.Array)) {
            dc.drawText(0, h / 2, Graphics.FONT_GLANCE, "approver: sin petición",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var p = pending as Lang.Array;
        var label   = (p.size() > 0) ? (p[0] as Lang.String) : "";
        var tool    = (p.size() > 1) ? (p[1] as Lang.String) : "";
        var summary = (p.size() > 2) ? (p[2] as Lang.String) : "";
        var line2 = summary.equals("") ? tool : (tool + ": " + summary);

        dc.drawText(0, h / 4, Graphics.FONT_GLANCE, label,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(0, (h * 3) / 4, Graphics.FONT_GLANCE, line2,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
