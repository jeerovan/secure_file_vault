import 'package:flutter/foundation.dart';

enum EventType {
  updateItem,
}

enum EventKey {
  object,
  uploadProgress,
  downloadProgress,
  added,
  uploaded,
  downloaded,
  removed
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

  // Method to publish a new event
  void publish(AppEvent event) {
    _eventNotifier.value = event;
  }

  // Getter for the notifier
  ValueNotifier<AppEvent?> get notifier => _eventNotifier;
}
