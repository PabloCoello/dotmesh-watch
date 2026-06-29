using Toybox.WatchUi;
using Toybox.Communications;
using Toybox.Application;
using Toybox.Lang;
using Toybox.PersistedContent;

// Menú de decisiones del approver. La primera fila muestra la última petición
// pendiente; se rellena con "Actualizar", que lee el topic REQ vía /raw. Debajo,
// las dos decisiones de permiso (topic DEC) y tres reprompts (topic REP). Los
// textos de los reprompts son EXACTAMENTE los que manda el bridge del host
// (lib.sh), así que la muñeca y los botones del push disparan lo mismo.
class ApproverMenu extends WatchUi.Menu2 {
    // Ventana de /raw. Se ciñe al timeout por defecto del host (BRIDGE_TIMEOUT=300s):
    // más allá, el host ya abandonó la petición y mostrarla solo confunde.
    const POLL_WINDOW = "5m";

    function initialize() {
        Menu2.initialize({ :title => "dotmesh" });
        addItem(new WatchUi.MenuItem("(sin petición)", "toca Actualizar", :pending, null));
        addItem(new WatchUi.MenuItem("Aprobar",    "permiso",  :allow,   null));
        addItem(new WatchUi.MenuItem("Denegar",    "permiso",  :deny,    null));
        addItem(new WatchUi.MenuItem("Continúa",   "reprompt", :cont,    null));
        addItem(new WatchUi.MenuItem("Tests",      "reprompt", :tests,   null));
        addItem(new WatchUi.MenuItem("Commit",     "reprompt", :commit,  null));
        addItem(new WatchUi.MenuItem("Actualizar", "leer lo pendiente", :refresh, null));
    }

    // Lee el topic REQ con GET /raw?poll=1&since=15m (TEXT_PLAIN) y refresca la
    // fila de pendiente. Sin reqTopic configurado, avisa y no hace nada.
    function refresh() {
        var base  = Application.Properties.getValue("baseUrl");
        var topic = Application.Properties.getValue("reqTopic");
        var token = Application.Properties.getValue("token");

        if (base == null || topic == null || base.equals("") || topic.equals("")) {
            WatchUi.showToast("Configura reqTopic", null);
            return;
        }

        // El host guarda la base sin barra final; el reloj concatena base+topic, así
        // que la exige. La añadimos si falta para no romper la URL del GET.
        var baseStr = base as Lang.String;
        if (!baseStr.substring(baseStr.length() - 1, baseStr.length()).equals("/")) {
            baseStr = baseStr + "/";
        }

        var headers = {};
        if (token != null && !token.equals("")) {
            headers.put("Authorization", "Bearer " + token);
        }

        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :headers      => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        var params = { "poll" => "1", "since" => POLL_WINDOW };

        Communications.makeWebRequest(baseStr + topic + "/raw", params, options, method(:onPoll));
        WatchUi.showToast("Actualizando…", null);
    }

    // Respuesta de /raw: 200 -> parsea y pinta; demasiado grande / error -> toast.
    function onPoll(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator) as Void {
        if (responseCode == 200) {
            applyPending(Bridge.requestRecords(data));
        } else if (responseCode == Communications.NETWORK_RESPONSE_TOO_LARGE) {
            WatchUi.showToast("Respuesta grande", null);
        } else {
            WatchUi.showToast("Error " + responseCode, null);
        }
    }

    // Vuelca la última petición en la fila :pending (título=label, subtítulo=tool
    // — summary) y la guarda en Bridge.pending para responder por id. Sin
    // peticiones, deja la fila en reposo.
    function applyPending(records as Lang.Array) as Void {
        var idx = findItemById(:pending);
        if (idx < 0) { return; }
        var it = getItem(idx);

        if (records.size() == 0) {
            Bridge.pending = null;
            it.setLabel("(sin petición)");
            it.setSubLabel("nada en " + POLL_WINDOW);
            WatchUi.requestUpdate();
            return;
        }

        var rec = records[records.size() - 1] as Lang.Dictionary;
        Bridge.pending = rec;
        it.setLabel(rec[:label] as Lang.String);
        var sub = rec[:tool] as Lang.String;
        var summary = rec[:summary] as Lang.String;
        if (!summary.equals("")) {
            sub = sub + " — " + summary;
        }
        it.setSubLabel(sub);
        WatchUi.requestUpdate();
    }
}

// Traduce cada entrada a (topic, mensaje) y publica en ntfy con makeWebRequest.
// Guarda una referencia al menú para poder refrescar la fila de pendiente.
class ApproverMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _menu;

    function initialize(menu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :allow) {
            decide("allow");
        } else if (id == :deny) {
            decide("deny");
        } else if (id == :cont) {
            send("repTopic", "continúa con lo siguiente");
        } else if (id == :tests) {
            send("repTopic", "ejecuta los tests y arregla lo que falle");
        } else if (id == :commit) {
            send("repTopic", "haz commit de los cambios");
        } else if (id == :refresh || id == :pending) {
            _menu.refresh();
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    // Responde el permiso correlacionando por id: publica "<id> allow|deny" en el
    // topic DEC (la forma que reconoce bridge_match del host, segura con varias
    // sesiones). Sin petición leída, avisa y no envía nada.
    function decide(verdict) {
        if (Bridge.pending == null) {
            WatchUi.showToast("Sin petición; Actualizar", null);
            return;
        }
        var rec = Bridge.pending as Lang.Dictionary;
        var pid = rec[:id] as Lang.String;
        send("decTopic", pid + " " + verdict);
        // Ya decidida: limpia la fila para no re-enviar una decisión obsoleta. La
        // resolución del host no vuelve por REQ, así que toca Actualizar otra vez.
        _menu.applyPending([]);
    }

    // Publica "message" en el topic configurado, usando el modo publish-as-JSON
    // de ntfy: POST al raíz con cuerpo {"topic":..., "message":...}.
    function send(topicKey, message) {
        var base  = Application.Properties.getValue("baseUrl");
        var topic = Application.Properties.getValue(topicKey);
        var token = Application.Properties.getValue("token");

        if (base == null || topic == null || base.equals("") || topic.equals("")) {
            WatchUi.showToast("Configura los topics", null);
            return;
        }

        var headers = {
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
        };
        if (token != null && !token.equals("")) {
            headers.put("Authorization", "Bearer " + token);
        }

        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_POST,
            :headers      => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        var params = {
            "topic"   => topic,
            "message" => message
        };

        Communications.makeWebRequest(base, params, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator) as Void {
        if (responseCode == 200) {
            WatchUi.showToast("Enviado", null);
        } else {
            WatchUi.showToast("Error " + responseCode, null);
        }
    }
}
