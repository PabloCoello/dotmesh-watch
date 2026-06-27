import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Punto de entrada de la aplicación (tipo watchface en el manifest).
class DotmeshWatchApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    // La vista inicial de una esfera debe extender WatchUi.WatchFace.
    function getInitialView() {
        return [ new DotmeshWatchView() ];
    }
}
