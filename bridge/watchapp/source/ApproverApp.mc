using Toybox.Application;
using Toybox.WatchUi;

// Entry point del approver. Lanza directamente el menú de decisiones.
class ApproverApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var menu = new ApproverMenu();
        return [ menu, new ApproverMenuDelegate(menu) ];
    }
}
