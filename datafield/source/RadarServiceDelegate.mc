using Toybox.System;
using Toybox.Communications;
using Toybox.Background;
using Toybox.Time;
using Toybox.Lang;
using Toybox.PersistedContent;

// Background worker: the ONLY context allowed to make web requests for a data
// field. Runs in a 32 KB memory pool, so it does as little as possible -- fetch
// the (RLE-compressed, ~2 KB) grid and hand it straight back.
//
// The payload is returned via Background.exit() rather than written to storage:
// storage writes from a background process need API level 3.2.0, while
// Background.exit() has worked since 2.3.0. The RLE payload is small enough to
// stay well under the 8 KB exit limit.
(:background)
class RadarServiceDelegate extends System.ServiceDelegate {

    // Plain-text grid published by the GitHub Actions proxy.
    const GRID_URL = "https://raw.githubusercontent.com/vidl21/arso-radar/gh-pages/grid.txt";

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Plain text (GitHub raw serves it as text/plain -> returned as a String).
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET
        };
        // The ?t= cache-buster matters: GitHub's raw CDN was observed serving a
        // stale grid for several minutes after the proxy updated it.
        Communications.makeWebRequest(GRID_URL, { "t" => Time.now().value() }, options, method(:onGrid));
    }

    function onGrid(code as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (code == 200 && data instanceof Lang.String) {
            Background.exit(data);     // String  -> the grid payload
        } else {
            Background.exit(code);     // Number  -> failure code, shown on screen
        }
    }
}
