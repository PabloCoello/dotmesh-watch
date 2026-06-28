using Toybox.Lang;
using Toybox.StringUtil;

// Lectura de las peticiones (REQ) que publica el host (bridge/approver/lib.sh).
// El cuerpo de cada petición es "id␟label␟tool␟summary" separado por US (0x1f);
// el reloj lo lee del topic REQ vía /raw y lo parte a mano. Las líneas SIN US
// (reprompts, avisos, preguntas) se ignoran: no son peticiones de permiso.
module Bridge {

    // Última petición pendiente leída (la más reciente), o null. La usa el
    // delegate para responder correlacionando por id. {:id,:label,:tool,:summary}.
    var pending = null;

    // El separador US (0x1f) como String, idéntico al de bridge_request_body.
    function us() as Lang.String {
        return StringUtil.charArrayToString([(0x1f).toChar()]);
    }

    // Parte "s" por cada aparición de "sep" en una lista de trozos.
    function splitBy(s, sep) as Lang.Array {
        var out = [];
        if (s == null) { return out; }
        var step = sep.length();
        if (step <= 0) { out.add(s); return out; }
        var rest = s;
        var i = rest.find(sep);
        while (i != null) {
            out.add(rest.substring(0, i));
            rest = rest.substring(i + step, rest.length());
            i = rest.find(sep);
        }
        out.add(rest);
        return out;
    }

    // Parte una línea por el separador US.
    function splitUS(line) as Lang.Array {
        return splitBy(line, us());
    }

    // Convierte "id␟label␟tool␟summary" en {:id,:label,:tool,:summary}. Devuelve
    // null si la línea no lleva US: entonces no es una petición de permiso.
    function parseRequestLine(line) as Lang.Dictionary or Null {
        if (line == null) { return null; }
        var f = splitUS(line);
        if (f.size() < 2) { return null; }
        return {
            :id      => f[0],
            :label   => f[1],
            :tool    => f.size() > 2 ? f[2] : "",
            :summary => f.size() > 3 ? f[3] : ""
        };
    }

    // Cuerpo TEXT_PLAIN de /raw (una línea por mensaje) -> lista de peticiones,
    // en orden de llegada (la última es la más reciente).
    function requestRecords(body) as Lang.Array {
        var records = [];
        if (body == null) { return records; }
        var lines = splitBy(body, "\n");
        for (var i = 0; i < lines.size(); i++) {
            var line = lines[i];
            if (line == null || line.equals("")) { continue; }
            var rec = parseRequestLine(line);
            if (rec != null) { records.add(rec); }
        }
        return records;
    }
}
