import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var externalWindow: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Main.storyboard から最初の画面（MainViewController）を読み込む
        // 多くの場合、プロジェクト設定の "Main Interface" に Main.storyboard が指定されていれば
        // 自動生成されるため、下記のコードは省略できる場合があります。
        // ただし省略すると window が生成されないプロジェクト構成の可能性もあるので、必要に応じて記述。
        
        if window == nil {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            // MainViewController は isInitialViewController のシーンを使う
            guard let mainVC = storyboard.instantiateInitialViewController() else {
                fatalError("Could not instantiate initial view controller from Main.storyboard")
            }
            let mainWindow = UIWindow(frame: UIScreen.main.bounds)
            mainWindow.rootViewController = mainVC
            mainWindow.makeKeyAndVisible()
            window = mainWindow
        }
        
        // 外部画面チェック
        checkForExternalScreens()

        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // 接続/切断されている可能性があるので再チェック
        checkForExternalScreens()
    }
    
    /// 外部ディスプレイの有無をチェックし、存在すれば externalWindow 生成＆表示
    private func checkForExternalScreens() {
        let screens = UIScreen.screens
        // screens[0] がメイン画面、screens[1] が外部ディスプレイ
        if screens.count > 1 {
            let externalScreen = screens[1]
            
            // すでに externalWindow があるなら使いまわし、無ければ作成
            if externalWindow == nil {
                externalWindow = UIWindow(frame: externalScreen.bounds)
                externalWindow?.screen = externalScreen
            }
            
            // Main.storyboard から ExternalDisplayViewController を生成
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let externalVC = storyboard
                .instantiateViewController(withIdentifier: "ExternalDisplayVC")
                    as? ExternalDisplayViewController
            else {
                fatalError("Could not instantiate ExternalDisplayViewController from Main.storyboard")
            }
            
            // MainViewController のインスタンスを取得して相互参照
            if let mainVC = window?.rootViewController as? MainViewController {
                mainVC.externalVC = externalVC
                externalVC.mainViewController = mainVC
            }
            // もし NavigationController をルートにしてるなら:
            else if let nav = window?.rootViewController as? UINavigationController,
                    let mainVC = nav.viewControllers.first as? MainViewController {
                mainVC.externalVC = externalVC
                externalVC.mainViewController = mainVC
            }
            
            // externalWindow にセットして表示
            externalWindow?.rootViewController = externalVC
            externalWindow?.isHidden = false
            
        } else {
            // 外部ディスプレイが無ければ外部ウィンドウを隠す
            externalWindow?.isHidden = true
            externalWindow = nil
        }
    }
}
