import { FlutterEngine } from '@ohos/flutter_ohos';

/**
 * OHOS-only capabilities live in the runner so the standard Flutter toolchain
 * never has to parse plugins with an unknown "ohos" platform declaration.
 */
export class GeneratedPluginRegistrant {
  static registerWith(_flutterEngine: FlutterEngine): void {
  }
}
