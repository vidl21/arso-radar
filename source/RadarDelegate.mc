using Toybox.WatchUi;

// Handles button input for the radar view.
// Edge 530 has physical buttons (no touch): the Start/Enter (lap) button
// triggers an immediate manual refresh; Back exits the app.
class RadarDelegate extends WatchUi.BehaviorDelegate {

    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Start/Enter (and the lap key map to onSelect on Edge devices).
    function onSelect() {
        _view.refresh();
        return true;
    }

    // Any unmapped key still forces a refresh, which is the only useful action.
    function onKey(evt) {
        _view.refresh();
        return true;
    }
}
