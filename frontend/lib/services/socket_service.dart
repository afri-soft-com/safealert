import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

typedef SosAlertCallback = void Function(Map<String, dynamic> alert);
typedef TripEventCallback = void Function(Map<String, dynamic> data);

class SocketService {
  static final SocketService _instance = SocketService._();
  SocketService._();
  factory SocketService() => _instance;

  io.Socket? _socket;
  SosAlertCallback? _onSosAlert;
  TripEventCallback? _onTripPing;
  TripEventCallback? _onEscortTrip;
  String? _userId;

  void setSosAlertHandler(SosAlertCallback? handler) {
    _onSosAlert = handler;
  }

  void setTripHandlers({
    TripEventCallback? onTripPing,
    TripEventCallback? onEscortTrip,
  }) {
    _onTripPing = onTripPing;
    _onEscortTrip = onEscortTrip;
  }

  void connect({String? userId}) {
    if (userId != null) _userId = userId;
    if (_socket?.connected == true) {
      _authenticate();
      return;
    }
    disconnect();

    _socket = io.io(
      ApiService.socketOrigin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
      _authenticate();
    });
    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
    _socket!.on('sos_alert', (data) {
      if (data is Map) {
        _onSosAlert?.call(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('sos_live', (data) {
      if (data is Map) {
        _onSosAlert?.call(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('trip_ping', (data) {
      if (data is Map) {
        _onTripPing?.call(Map<String, dynamic>.from(data));
      }
    });
    _socket!.on('escort_trip', (data) {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final trip = map['trip'];
        if (trip is Map) {
          _onEscortTrip?.call(Map<String, dynamic>.from(trip));
        } else {
          _onEscortTrip?.call(map);
        }
      }
    });
  }

  void _authenticate() {
    final id = _userId;
    if (id == null || id.isEmpty || _socket == null) return;
    _socket!.emit('authenticate', {'userId': id});
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
