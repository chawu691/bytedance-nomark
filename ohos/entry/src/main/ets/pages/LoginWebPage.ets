import webview from '@ohos.web.webview';
import { router } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';

const LOGIN_RESULT_EVENT_ID = 1001;
// 移动端 UA（伪装 Pixel 10 / Android Chrome）
// 桌面端 UA 容易触发抖音扫码风控，改用移动端伪装以走手机号/验证码登录流程
const PC_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 15; Pixel 10) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

@Entry
@Component
struct LoginWebPage {
  @State url: string = '';
  controller: webview.WebController = new webview.WebController();
  webCookieManager: webCookie.WebCookieManager = webCookie.WebCookieManager.getInstance();
  targetHost: string = '';
  private hasResult: boolean = false;

  aboutToAppear() {
    const params = router.getParams() as Record<string, Object>;
    this.url = params.url as string;
    this.targetHost = params.targetHost as string;
    // PC UA 伪装，加载桌面端网页
    this.controller.setUserAgent(PC_USER_AGENT);
  }

  private sendResultAndBack(cookieStr: string) {
    if (this.hasResult) return;
    this.hasResult = true;
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
          // 用 WebCookieManager 获取 HttpOnly Cookie（document.cookie 取不到）
          // 仅 sessionid 是登录态标志；ttwid 是首次访问就下发的跟踪 Cookie，不能作为登录判据
          this.webCookieManager.fetchCookie('https://' + this.targetHost)
            .then((cookieStr: string) => {
              if (cookieStr.includes('sessionid=')) {
                this.sendResultAndBack(cookieStr);
              }
            })
            .catch(() => {});
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
    // 确保离开页面时一定有结果返回
    this.sendResultAndBack('');
  }
}
