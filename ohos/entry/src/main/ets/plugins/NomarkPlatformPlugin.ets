import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  Any,
  FlutterPlugin,
  MethodCall,
  MethodChannel
} from '@ohos/flutter_ohos';
import { FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

const CHANNEL = 'io.github.bytedance_nomark/platform';
const STORE_NAME = 'nomark_preferences';
const PREFERENCE_KEYS: string[] = [
  'settings_defaultMode',
  'settings_autoParse',
  'history_items'
];

interface MediaInput {
  path: string;
  mediaType: string;
  fileName: string;
}

export default class NomarkPlatformPlugin implements FlutterPlugin {
  private channel?: MethodChannel;
  private context?: common.Context;
  private abilityContext: common.UIAbilityContext;

  constructor(abilityContext: common.UIAbilityContext) {
    this.abilityContext = abilityContext;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    const plugin = this;
    this.channel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        plugin.handle(call, result);
      }
    });
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.context = undefined;
  }

  getUniqueClassName(): string {
    return 'NomarkPlatformPlugin';
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case 'loadPreferences':
          result.success(await this.loadPreferences());
          return;
        case 'setPreference':
          await this.setPreference(
            call.argument('key') as string,
            call.argument('value')
          );
          result.success(null);
          return;
        case 'removePreference':
          await this.removePreference(call.argument('key') as string);
          result.success(null);
          return;
        case 'getCacheDir':
          result.success(this.requireContext().cacheDir);
          return;
        case 'openMedia':
          await this.abilityContext.startAbility({
            action: 'ohos.want.action.viewData',
            uri: call.argument('url') as string,
            type: 'video/*'
          });
          result.success(null);
          return;
        case 'saveMediaBatch':
          result.success(await this.saveMediaBatch(
            call.argument('files') as Array<Any>
          ));
          return;
        default:
          result.notImplemented();
      }
    } catch (error) {
      const businessError = error as BusinessError;
      result.error(
        businessError.code?.toString() ?? 'PLATFORM_ERROR',
        businessError.message ?? 'HarmonyOS platform operation failed',
        null
      );
    }
  }

  private requireContext(): common.Context {
    if (this.context === undefined) {
      throw new Error('Flutter plugin is not attached');
    }
    return this.context;
  }

  private async preferenceStore(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.requireContext(), {
      name: STORE_NAME
    });
  }

  private async loadPreferences(): Promise<Map<string, Any>> {
    const store = await this.preferenceStore();
    const values = new Map<string, Any>();
    for (const key of PREFERENCE_KEYS) {
      if (store.has(key)) {
        values.set(key, store.get(key, ''));
      }
    }
    return values;
  }

  private async setPreference(key: string, value: Any): Promise<void> {
    if (typeof value !== 'string' && typeof value !== 'boolean') {
      throw new Error('Only string and boolean preferences are supported');
    }
    const store = await this.preferenceStore();
    await store.put(key, value);
    await store.flush();
  }

  private async removePreference(key: string): Promise<void> {
    const store = await this.preferenceStore();
    await store.delete(key);
    await store.flush();
  }

  private readField(input: Any, key: string): Any {
    if (input instanceof Map) {
      return (input as Map<Any, Any>).get(key);
    }
    return input[key];
  }

  private parseMedia(input: Any): MediaInput {
    return {
      path: this.readField(input, 'path') as string,
      mediaType: this.readField(input, 'mediaType') as string,
      fileName: this.readField(input, 'fileName') as string
    };
  }

  private extension(fileName: string): string {
    const index = fileName.lastIndexOf('.');
    return index >= 0 ? fileName.substring(index + 1) : '';
  }

  private title(fileName: string): string {
    const index = fileName.lastIndexOf('.');
    return index > 0 ? fileName.substring(0, index) : fileName;
  }

  private async saveMediaBatch(rawFiles: Array<Any>): Promise<Map<string, Any>> {
    const files = rawFiles.map((raw) => this.parseMedia(raw));
    const sourceUris = files.map((file) => fileUri.getUriFromPath(file.path));
    const configs: Array<photoAccessHelper.PhotoCreationConfig> =
      files.map((file) => ({
        title: this.title(file.fileName),
        fileNameExtension: this.extension(file.fileName),
        photoType: file.mediaType === 'video'
          ? photoAccessHelper.PhotoType.VIDEO
          : photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }));
    const response = new Map<string, Any>();
    const savedIndices: number[] = [];
    const errors = new Map<number, string>();

    let destinationUris: string[];
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(
        this.requireContext()
      );
      destinationUris = await helper.showAssetsCreationDialog(
        sourceUris,
        configs
      );
    } catch (_error) {
      response.set('savedIndices', savedIndices);
      response.set('errors', errors);
      response.set('cancelled', true);
      return response;
    }
    if (destinationUris.length === 0) {
      response.set('savedIndices', savedIndices);
      response.set('errors', errors);
      response.set('cancelled', true);
      return response;
    }

    for (let index = 0; index < files.length; index += 1) {
      let source: fileIo.File | undefined;
      let destination: fileIo.File | undefined;
      try {
        if (index >= destinationUris.length) {
          errors.set(index, 'No destination URI was returned for this item');
          continue;
        }
        source = await fileIo.open(
          sourceUris[index],
          fileIo.OpenMode.READ_ONLY
        );
        destination = await fileIo.open(
          destinationUris[index],
          fileIo.OpenMode.WRITE_ONLY
        );
        await fileIo.copyFile(source.fd, destination.fd);
        savedIndices.push(index);
      } catch (error) {
        const businessError = error as BusinessError;
        errors.set(
          index,
          businessError.message ?? 'Failed to copy media into Photos'
        );
      } finally {
        if (source !== undefined) {
          fileIo.closeSync(source);
        }
        if (destination !== undefined) {
          fileIo.closeSync(destination);
        }
      }
    }

    response.set('savedIndices', savedIndices);
    response.set('errors', errors);
    response.set('cancelled', false);
    return response;
  }
}
