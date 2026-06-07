using Toybox.Application;

// Application entry point. Creates the single full-screen radar view.
class RadarApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    // Return the initial view and its input delegate.
    function getInitialView() {
        var view = new RadarView();
        return [ view, new RadarDelegate(view) ];
    }
}
