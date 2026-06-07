using Toybox.System;
using Toybox.Communications;
using Toybox.Background;
using Toybox.Time;
using Toybox.Lang;
using Toybox.PersistedContent;

// Background worker: the ONLY context allowed to make web requests for a data
// field. Fetches the small rain-grid JSON and returns it to the app.
(:background)
class RadarServiceDelegate extends System.ServiceDelegate {

    // *** EDIT THIS *** to your proxy's gh-pages raw grid URL (plain-text form):
    const GRID_URL = "https://raw.githubusercontent.com/vidl21/arso-radar/gh-pages/grid.txt";

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Plain text (GitHub raw serves it as text/plain -> returned as a String).
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET
        };
        Communications.makeWebRequest(GRID_URL, { "t" => Time.now().value() }, options, method(:onGrid));
    }

    function onGrid(code as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (code == 200 && data instanceof Lang.String) {
            Background.exit(data);     // hand the grid text back to the app
        } else {
            Background.exit(null);
        }
    }
}
