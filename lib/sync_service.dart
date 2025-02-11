import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

class SyncOrder {
  String localPath;
  String syncType; // Upload Only, Download Only, etc.
  bool isRunning;
  String remotePath;
  String fld_id;

  SyncOrder({
    required this.localPath,
    required this.syncType,
    this.isRunning = false,
    required this.remotePath,
    required this.fld_id,
  });

  // Convert SyncOrder to JSON
  Map<String, dynamic> toJson() {
    return {
      'localPath': localPath,
      'syncType': syncType,
      'isRunning': isRunning,
      'remotePath': remotePath,
      'fld_id': fld_id,
    };
  }

  // Create SyncOrder from JSON
  factory SyncOrder.fromJson(Map<String, dynamic> json) {
    return SyncOrder(
      localPath: json['localPath'],
      syncType: json['syncType'],
      isRunning: json['isRunning'] ?? false,
      remotePath: json['remotePath'],
      fld_id: json['fld_id'],
    );
  }
}

class SyncService {
  static const String SYNC_TASK = "sync_task";

  /// Load sync orders from storage
  Future<List<SyncOrder>> _loadSyncOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedOrders = prefs.getString('sync_orders');
    if (storedOrders != null) {
      List<dynamic> decoded = jsonDecode(storedOrders);
      return decoded.map((e) => SyncOrder.fromJson(e)).toList();
    }
    return [];
  }

  /// Perform sync for all active orders
  Future<void> _performSync() async {
    List<SyncOrder> syncOrders = await _loadSyncOrders();

    for (var order in syncOrders) {
      if (order.isRunning) {
        print("Syncing: ${order.localPath} (${order.syncType})");
        // TODO: Implement actual sync logic (upload/download files)
      }
    }
  }

  /// Register background sync task
  Future<void> startBackgroundSync() async {
    await Workmanager().initialize(
      _callbackDispatcher,
      isInDebugMode: true, // Set to false in production
    );
    await Workmanager().registerPeriodicTask(
      SYNC_TASK,
      SYNC_TASK,
      frequency: Duration(minutes: 1), // Adjust the sync interval
    );
  }

  /// Start sync on app launch
  Future<void> startSyncOnAppLaunch() async {
    List<SyncOrder> syncOrders = await _loadSyncOrders();
    bool hasRunningSync = syncOrders.any((order) => order.isRunning);
    if (hasRunningSync) {
      await startBackgroundSync();
    }
  }
}

/// Background sync callback
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    SyncService syncService = SyncService();
    await syncService._performSync();
    return Future.value(true);
  });
}
