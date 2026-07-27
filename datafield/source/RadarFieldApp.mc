using Toybox.Application;
using Toybox.Background;
using Toybox.Time;
using Toybox.Lang;
using Toybox.WatchUi;

// Data-field entry point with a background service.
//
// A data field cannot make web requests itself, so a background service
// (RadarServiceDelegate) fetches the rain grid and hands it back through
// Background.exit(); this class persists it for the field to draw.
//
// The (:background) annotation is REQUIRED: only annotated code is compiled into
// the background service, and the application object must be reachable there or
// getServiceDelegate() is never called and the service never runs.
(:background)
class RadarFieldApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Register once (re-registering restarts the 5-minute countdown), from
        // onStart rather than initialize() and wrapped in try/catch: if this
        // throws while the app object is being built, the device cannot start
        // the field at all and shows the launcher icon instead. A failed
        // registration must only cost auto-refresh, never the whole field.
        try {
            if (Toybox has :Background) {
                if (Background.getTemporalEventRegisteredTime() == null) {
                    Background.registerForTemporalEvent(new Time.Duration(300));
                }
            }
        } catch (ex) {
            // Ignore: the field still renders whatever data is already stored.
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

    // Result from the background service: a String is the grid payload, a Number
    // is a failure code. Persisting here (foreground) avoids depending on
    // background storage writes, which need API 3.2.0.
    function onBackgroundData(data) {
        if (data instanceof Lang.String) {
            Application.Storage.setValue("grid", data);
            Application.Storage.setValue("err", 0);
        } else if (data instanceof Lang.Number) {
            Application.Storage.setValue("err", data);
        }
        WatchUi.requestUpdate();
    }

    // Redraw when the user changes the zoom (or any setting).
    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}
