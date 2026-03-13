//
//  iOSAppDelegate.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(iOS)
import UIKit

@main
final class iOSAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    #if os(iOS)

    #endif
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = iOSViewController()
        // 需要设置背景色
        // window.rootViewController = UINavigationController(rootViewController: iOSViewController())
        // 不设置背景色，甚至不会触发-[UIApplication sendEvent:]
        // window.backgroundColor = .systemBackground
        window.backgroundColor = .white
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

}
#endif
