/// Shared map zoom levels — street/neighborhood scale so movement is visible.
abstract final class MapZoom {
  /// Community / incident map before GPS fix.
  static const communityInitial = 14.0;

  /// After locking GPS on the community map.
  static const communityGps = 15.0;

  /// Family circle: single member or initial view.
  static const circleFocus = 16.0;

  /// Family circle: initial map before members load.
  static const circleInitial = 15.0;

  /// Secure trip planner.
  static const tripInitial = 14.0;
  static const tripPlace = 15.0;

  /// Live escort follow.
  static const escortFollow = 16.0;
}
