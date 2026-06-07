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

    // *** EDIT THIS *** to your proxy's gh-pages raw grid URL:
    const GRID_URL = "https://raw.githubusercontent.com/USERNAME/REPO/gh-pages/grid.json";

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(GRID_URL, { "t" => Time.now().value() }, options, method(:onGrid));
    }

    function onGrid(code as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (code == 200 && data instanceof Lang.Dictionary) {
            Background.exit(data);     // hand the grid back to the app
        } else {
            Background.exit(null);
        }
    }
}
