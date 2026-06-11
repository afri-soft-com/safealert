import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

typedef SosAlertCallback = void Function(Map<String, dynamic> alert);

class SocketService {
  static final SocketService _instance = SocketService._();
  SocketService._();
  factory SocketService() => _instance;

  io.Socket? _socket;
  SosAlertCallback? _onSosAlert;

  void setSosAlertHandler(SosAlertCallback? handler) {
    _onSosAlert = handler;
  }

  void connect() {
    if (_socket?.connected == true) return;
    disconnect();

    _socket = io.io(
      ApiService.socketOrigin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => debugPrint('Socket connected'));
    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
    _socket!.on('sos_alert', (data) {
      if (data is Map) {
        _onSosAlert?.call(Map<String, dynamic>.from(data));
      }
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
