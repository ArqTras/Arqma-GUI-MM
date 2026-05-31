import BackgroundTasks
import Flutter
import UIKit

private let bgSyncChannelName = "com.arqma.wallet/ios_background_sync"
private let walletSyncProcessingTaskId = "com.arqma.arqmaWalletMobile.wallet-sync"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var bgSyncChannel: FlutterMethodChannel?
  private var activeBackgroundTasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextBackgroundTaskKey = 1

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: walletSyncProcessingTaskId,
        using: nil
      ) { task in
        self.handleWalletSyncProcessingTask(task as! BGProcessingTask)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    bgSyncChannel = FlutterMethodChannel(name: bgSyncChannelName, binaryMessenger: messenger)
    bgSyncChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate deallocated", details: nil))
        return
      }
      switch call.method {
      case "beginBackgroundSync":
        result(self.beginBackgroundSync())
      case "endBackgroundSync":
        if let args = call.arguments as? [String: Any],
           let taskKey = args["taskKey"] as? Int {
          self.endBackgroundSync(taskKey: taskKey)
        }
        result(nil)
      case "scheduleProcessingSync":
        self.scheduleProcessingSync()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginBackgroundSync() -> Int {
    let taskKey = nextBackgroundTaskKey
    nextBackgroundTaskKey += 1

    var bgTaskId = UIBackgroundTaskIdentifier.invalid
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "ArqmaWalletSync") { [weak self] in
      self?.onBackgroundTaskExpiring(taskKey: taskKey)
    }

    if bgTaskId != UIBackgroundTaskIdentifier.invalid {
      activeBackgroundTasks[taskKey] = bgTaskId
    } else {
      return -1
    }
    return taskKey
  }

  private func endBackgroundSync(taskKey: Int) {
    guard let bgTaskId = activeBackgroundTasks.removeValue(forKey: taskKey) else {
      return
    }
    UIApplication.shared.endBackgroundTask(bgTaskId)
  }

  private func onBackgroundTaskExpiring(taskKey: Int) {
    endBackgroundSync(taskKey: taskKey)
    bgSyncChannel?.invokeMethod(
      "backgroundTaskExpiring",
      arguments: ["taskKey": taskKey]
    )
  }

  private func scheduleProcessingSync() {
    guard #available(iOS 13.0, *) else {
      return
    }
    let request = BGProcessingTaskRequest(identifier: walletSyncProcessingTaskId)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("[ArqmaWallet] BGProcessingTask submit failed: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private func handleWalletSyncProcessingTask(_ task: BGProcessingTask) {
    var finished = false
    task.expirationHandler = {
      if !finished {
        finished = true
        task.setTaskCompleted(success: false)
      }
    }

    bgSyncChannel?.invokeMethod("performBackgroundWalletSync", arguments: nil) { _ in
      if finished {
        return
      }
      finished = true
      task.setTaskCompleted(success: true)
      self.scheduleProcessingSync()
    }
  }
}
