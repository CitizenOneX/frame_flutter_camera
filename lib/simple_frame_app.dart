import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'brilliant_bluetooth.dart';

/// basic State Machine for the app; mostly for bluetooth lifecycle,
/// all app activity expected to take place during "running" state
enum ApplicationState {
  disconnected,
  scanning,
  connecting,
  ready,
  running,
  stopping,
  disconnecting,
}

final _log = Logger("SimpleFrameApp");

mixin SimpleFrameAppState<T extends StatefulWidget> on State<T> {
  ApplicationState currentState = ApplicationState.disconnected;

  // Use BrilliantBluetooth for communications with Frame
  BrilliantDevice? connectedDevice;
  StreamSubscription? _scanStream;
  StreamSubscription<BrilliantDevice>? _deviceStateSubs;

  Future<void> scanForFrame() async {
    currentState = ApplicationState.scanning;
    if (mounted) setState(() {});

    await BrilliantBluetooth.requestPermission();

    await _scanStream?.cancel();
    _scanStream = BrilliantBluetooth.scan()
      .timeout(const Duration(seconds: 5), onTimeout: (sink) {
        // Scan timeouts can occur without having found a Frame, but also
        // after the Frame is found and being connected to, even though
        // the first step after finding the Frame is to stop the scan.
        // In those cases we don't want to change the application state back
        // to disconnected
        switch (currentState) {
          case ApplicationState.scanning:
            _log.fine('Scan timed out after 5 seconds');
            currentState = ApplicationState.disconnected;
            if (mounted) setState(() {});
            break;
          case ApplicationState.connecting:
            // found a device and started connecting, just let it play out
            break;
          case ApplicationState.ready:
          case ApplicationState.running:
            // already connected, nothing to do
            break;
          default:
            _log.fine('Unexpected state on scan timeout: $currentState');
            if (mounted) setState(() {});
        }
      })
      .listen((device) {
        _log.fine('Frame found, connecting');
        currentState = ApplicationState.connecting;
        if (mounted) setState(() {});

        connectToScannedFrame(device);
      });
  }

  Future<void> connectToScannedFrame(BrilliantScannedDevice device) async {
    try {
      _log.fine('connecting to scanned device: $device');
      connectedDevice = await BrilliantBluetooth.connect(device);
      _log.fine('device connected: ${connectedDevice!.device.remoteId}');

      // subscribe to connection state for the device to detect disconnections
      // so we can transition the app to a disconnected state
      await _deviceStateSubs?.cancel();
      _deviceStateSubs = connectedDevice!.connectionState.listen((bd) {
        _log.fine('Frame connection state change: ${bd.state.name}');
        if (bd.state == BrilliantConnectionState.disconnected) {
          currentState = ApplicationState.disconnected;
          _log.fine('Frame disconnected: currentState: $currentState');
          if (mounted) setState(() {});
        }
      });

      try {
        // terminate the main.lua (if currently running) so we can run our lua code
        // TODO looks like if the signal comes too early after connection, it isn't registered
        await Future.delayed(const Duration(milliseconds: 500));
        await connectedDevice!.sendBreakSignal();

        // Application is ready to go!
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});

      } catch (e) {
        currentState = ApplicationState.disconnected;
        _log.fine('Error while sending break signal: $e');
        if (mounted) setState(() {});

        disconnectFrame();
      }
    } catch (e) {
      currentState = ApplicationState.disconnected;
      _log.fine('Error while connecting and/or discovering services: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> reconnectFrame() async {
    if (connectedDevice != null) {
      try {
        _log.fine('connecting to existing device: $connectedDevice');
        // TODO get the BrilliantDevice return value from the reconnect call?
        // TODO am I getting duplicate devices/subscriptions?
        // Rather than fromUuid(), can I just call connectedDevice.device.connect() myself?
        await BrilliantBluetooth.reconnect(connectedDevice!.uuid);
        _log.fine('device connected: $connectedDevice');

        // subscribe to connection state for the device to detect disconnections
        // and transition the app to a disconnected state
        await _deviceStateSubs?.cancel();
        _deviceStateSubs = connectedDevice!.connectionState.listen((bd) {
          _log.fine('Frame connection state change: ${bd.state.name}');
          if (bd.state == BrilliantConnectionState.disconnected) {
            currentState = ApplicationState.disconnected;
            _log.fine('Frame disconnected');
            if (mounted) setState(() {});
          }
        });

        try {
          // terminate the main.lua (if currently running) so we can run our lua code
          // TODO looks like if the signal comes too early after connection, it isn't registered
          await Future.delayed(const Duration(milliseconds: 500));
          await connectedDevice!.sendBreakSignal();

          // Application is ready to go!
          currentState = ApplicationState.ready;
          if (mounted) setState(() {});

        } catch (e) {
          currentState = ApplicationState.disconnected;
          _log.fine('Error while sending break signal: $e');
          if (mounted) setState(() {});

        disconnectFrame();
        }
      } catch (e) {
        currentState = ApplicationState.disconnected;
        _log.fine('Error while connecting and/or discovering services: $e');
        if (mounted) setState(() {});
      }
    }
    else {
      currentState = ApplicationState.disconnected;
      _log.fine('Current device is null, reconnection not possible');
      if (mounted) setState(() {});
    }
  }

  Future<void> scanOrReconnectFrame() async {
    if (connectedDevice != null) {
      return reconnectFrame();
    }
    else {
      return scanForFrame();
    }
  }

  Future<void> disconnectFrame() async {
    if (connectedDevice != null) {
      try {
        _log.fine('Disconnecting from Frame');
        // break first in case it's sleeping - otherwise the reset won't work
        await connectedDevice!.sendBreakSignal();
        _log.fine('Break signal sent');
        // TODO the break signal needs some more time to be processed before we can reliably send the reset signal, by the looks of it
        await Future.delayed(const Duration(milliseconds: 500));

        // try to reset device back to running main.lua
        await connectedDevice!.sendResetSignal();
        _log.fine('Reset signal sent');
        // TODO the reset signal doesn't seem to be processed in time if we disconnect immediately, so we introduce a delay here to give it more time
        // The sdk's sendResetSignal actually already adds 100ms delay
        // perhaps it's not quite enough.
        await Future.delayed(const Duration(milliseconds: 500));

      } catch (e) {
          _log.fine('Error while sending reset signal: $e');
      }

      try{
          // try to disconnect cleanly if the device allows
          await connectedDevice!.disconnect();
      } catch (e) {
          _log.fine('Error while calling disconnect(): $e');
      }
    }
    else {
      _log.fine('Current device is null, disconnection not possible');
    }

    currentState = ApplicationState.disconnected;
    if (mounted) setState(() {});
  }

  /// the SimpleFrameApp subclass provides the application-specific code
  Future<void> runApplication();

  /// the SimpleFrameApp subclass provides the application-specific code
  Future<void> stopApplication();

}
