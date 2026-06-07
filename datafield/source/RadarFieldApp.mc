using Toybox.Application;
using Toybox.Background;
using Toybox.Time;
using Toybox.WatchUi;

// Data-field entry point with a background service.
//
// A data field cannot make web requests itself, so a background service
// (RadarServiceDelegate) fetches the rain grid every 5 min and hands it back via
// onBackgroundData(); the field reads it from storage and draws it.
class RadarFieldApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Register the recurring background fetch (5 min is the platform minimum).
        if (Toybox has :Background) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        }
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new RadarField() ];
    }

    // Provide the background worker.
    function getServiceDelegate() {
        return [ new RadarServiceDelegate() ];
    }

    // The background service writes the grid straight to storage; this just
    // signals the field to redraw. (data is a Boolean success flag.)
    function onBackgroundData(data) {
        WatchUi.requestUpdate();
    }
}
