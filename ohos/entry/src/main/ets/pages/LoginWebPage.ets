import webview from '@ohos.web.webview';
import { router } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';

const LOGIN_RESULT_EVENT_ID = 1001;
const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 15; Pixel 10) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

@Entry
@Component
struct LoginWebPage {
  @State url: string = '';
  controller: webview.WebController = new webview.WebController();
  webCookieManager: webCookie.WebCookieManager = webCookie.WebCookieManager.getInstance();
  targetHost: string = '';
  cookieUrls: Array<string> = [];
  cookieKeys: Array<string> = [];
  successCookieKeys: Array<string> = ['sessionid'];
  private hasResult: boolean = false;
  private pollTimer: number = -1;

  aboutToAppear() {
    const params = router.getParams() as Record<string, Object>;
    this.url = params.url as string;
    this.targetHost = params.targetHost as string;
    this.cookieUrls = (params.cookieUrls as Array<string>) ?? ['https://' + this.targetHost + '/'];
    this.cookieKeys = (params.cookieKeys as Array<string>) ?? [];
    this.successCookieKeys = (params.successCookieKeys as Array<string>) ?? ['sessionid'];
    this.controller.setUserAgent((params.userAgent as string) ?? DEFAULT_USER_AGENT);
    this.pollTimer = setInterval(() => {
      this.checkCookies();
    }, 2000);
  }

  private async checkCookies(): Promise<void> {
    if (this.hasResult) return;
    const cookieMap = new Map<string, string>();
    for (const cookieUrl of this.cookieUrls) {
      try {
        const cookieStr = await this.webCookieManager.fetchCookie(cookieUrl);
        for (const part of cookieStr.split(';')) {
          const separator = part.indexOf('=');
          if (separator <= 0) continue;
          const name = part.substring(0, separator).trim();
          const value = part.substring(separator + 1).trim();
          if (this.cookieKeys.includes(name) && value.length > 0) {
            cookieMap.set(name, value);
          }
        }
      } catch (error) {}
    }
    if (!this.successCookieKeys.some((key) => (cookieMap.get(key) ?? '').length > 0)) {
      return;
    }
    const cookies: Array<string> = [];
    cookieMap.forEach((value: string, key: string) => {
      cookies.push(key + '=' + value);
    });
    this.sendResultAndBack(cookies.join('; '));
  }

  private sendResultAndBack(cookieStr: string) {
    if (this.hasResult) return;
    this.hasResult = true;
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    emitter.emit(
      { id: LOGIN_RESULT_EVENT_ID },
      { data: { cookieStr: cookieStr } }
    );
    router.back();
  }

  build() {
    Column() {
      Web({ src: this.url, controller: this.controller })
        .domStorageAccess(true)
        .databaseAccess(true)
        .onPageEnd(() => {
          // 周期轮询用于捕获异步写入的 HttpOnly Cookie；页面结束时也立即检查一次。
          this.checkCookies();
        })
        .width('100%')
        .height('100%')
    }
  }

  onBackPress(): boolean {
    // 用户手动返回，发送空结果
    this.sendResultAndBack('');
    return true;
  }

  aboutToDisappear() {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    // 确保离开页面时一定有结果返回
    this.sendResultAndBack('');
  }
}
