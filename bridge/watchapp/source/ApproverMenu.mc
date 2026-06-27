using Toybox.WatchUi;
using Toybox.Communications;
using Toybox.Application;
using Toybox.Lang;
using Toybox.PersistedContent;

// Menú de decisiones: dos para el permiso (topic DEC) y tres reprompts (topic
// REP). Los textos son EXACTAMENTE los que manda el bridge del host (lib.sh), así
// que la muñeca y los botones del push disparan lo mismo.
class ApproverMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "dotmesh" });
        addItem(new WatchUi.MenuItem("Aprobar",  "permiso",  :allow,  null));
        addItem(new WatchUi.MenuItem("Denegar",  "permiso",  :deny,   null));
        addItem(new WatchUi.MenuItem("Continúa", "reprompt", :cont,   null));
        addItem(new WatchUi.MenuItem("Tests",    "reprompt", :tests,  null));
        addItem(new WatchUi.MenuItem("Commit",   "reprompt", :commit, null));
    }
}

// Traduce cada entrada a (topic, mensaje) y publica en ntfy con makeWebRequest.
class ApproverMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :allow) {
            send("decTopic", "allow");
        } else if (id == :deny) {
            send("decTopic", "deny");
        } else if (id == :cont) {
            send("repTopic", "continúa con lo siguiente");
        } else if (id == :tests) {
            send("repTopic", "ejecuta los tests y arregla lo que falle");
        } else if (id == :commit) {
            send("repTopic", "haz commit de los cambios");
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
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
