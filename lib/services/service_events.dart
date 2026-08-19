import 'dart:async';

import 'package:flutter/foundation.dart';

enum EventType { settings, system }

enum EventKey {
  object,
  uploadProgress,
  downloadProgress,
  added,
  updated,
  uploaded,
  downloaded,
  removed,
  running,
  stopped,
  logging,
  signout,
  storageFull,
}

class ForegroundSyncStateMessage {
  static const String _typeKey = 'type';
  static const String _typeValue = 'foregroundSyncState';
  static const String _isRunningKey = 'isRunning';

  static Map<String, Object> encode({required bool isRunning}) => {
        _typeKey: _typeValue,
        _isRunningKey: isRunning,
      };

  static bool? decode(Object data) {
    if (data is! Map || data[_typeKey] != _typeValue) return null;
    final isRunning = data[_isRunningKey];
    return isRunning is bool ? isRunning : null;
  }
}

class AppEvent {
  final EventType type;
  final String id;
  final EventKey key;
  final dynamic value;

  AppEvent({
    required this.type,
    required this.id,
    required this.key,
    this.value,
  });

  @override
  String toString() => 'AppEvent(type: $type,id: $id, key: $key,value: $value)';
}

/// A singleton class that provides an event stream using ValueNotifier
class EventStream {
  // Private constructor
  EventStream._();

  // Singleton instance
  static final EventStream _instance = EventStream._();

  // Factory constructor to return the singleton instance
  factory EventStream() => _instance;

  // ValueNotifier to hold and notify about event data
  final ValueNotifier<AppEvent?> _eventNotifier = ValueNotifier(null);
  final StreamController<AppEvent> _eventController =
      StreamController<AppEvent>.broadcast(sync: true);

  // Method to publish a new event
  void publish(AppEvent event) {
    _eventNotifier.value = event;
    _eventController.add(event);
  }

  // Getter for the notifier
  ValueNotifier<AppEvent?> get notifier => _eventNotifier;
  Stream<AppEvent> get events => _eventController.stream;
}
