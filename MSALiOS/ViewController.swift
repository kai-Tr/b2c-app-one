//------------------------------------------------------------------------------
//
// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//------------------------------------------------------------------------------

import UIKit
import MSAL
import KeychainSwift
import SwiftyJSON
import ObjectMapper

/// 😃 A View Controller that will respond to the events of the Storyboard.

//public class MyMSALAccount: MSALAccount {

//    public func encode(with coder: NSCoder) {
//        coder.encode(account, forKey: "account")
//    }
//
//    public required init?(coder: NSCoder) {
////        account = coder.decodeObject(forKey: "account") as! MSALAccount
//        super.init()
//    }

//}

class MyMSALTenantProfile: MSALTenantProfile, Codable {}

class MyMSALAccount: Codable {
    var identifier: String?
    var username: String?
    var accountClaims: Dictionary<String, String>?
    var tenantProfiles: [MyMSALTenantProfile]?
    init() {}
}

class ViewController: UIViewController, UITextFieldDelegate, URLSessionDelegate {
    
    let keychain = KeychainSwift()
    let keyChainAccountIdentifierName = "accountIdentifier"
    let accessGroup = "R4GPLKA7H6.com.microsoft.adalcache"
    let kTenantName = "stpocb2c.onmicrosoft.com" // Your tenant name
    let kAuthorityHostName = "stpocb2c.b2clogin.com" // Your authority host name
    let kClientID = "fab7a30d-ccb9-49bc-afec-64bca7ca1e9e" // Your client ID from the portal when you created your application
    let kSignupOrSigninPolicy = "B2C_1_poc_signup_signin" // Your signup and sign-in policy you created in the portal
    let kEditProfilePolicy = "B2C_1_PoC_EditProfile"
    let kEndpoint = "https://%@/tfp/%@/%@"
    
    // Update the below to your client ID you received in the portal. The below is for running the demo only
    
    let kGraphEndpoint = "https://graph.microsoft.com/"
//    let kAuthority = "https://login.microsoftonline.com/872ef26f-f5ba-497e-8c0b-79279645f2df"
    let kRedirectUri = "msauth.vn.saigonthink.ssob2cidentity://auth"
    
    let kScopes: [String] = ["https://stpocb2c.onmicrosoft.com/api/app.read.all"]
    
    var accessToken = String()
    var applicationContext : MSALPublicClientApplication?
    var webViewParamaters : MSALWebviewParameters?

    var loggingText: UITextView!
    var signOutButton: UIButton!
    var callGraphButton: UIButton!
    var usernameLabel: UILabel!
    
    var currentAccount: MSALAccount?

    /**
        Setup public client application in viewDidLoad
    */

    override func viewDidLoad() {

        super.viewDidLoad()

        initUI()
        
        keychain.accessGroup = self.accessGroup
        do {
            try self.initMSAL()
        } catch let error {
            self.updateLogging(text: "Unable to create Application Context \(error)")
        }
        
        self.loadCurrentAccount()
        self.platformViewDidLoadSetup()
    }
    
    func platformViewDidLoadSetup() {
                
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appCameToForeGround(notification:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
    }

    override func viewWillAppear(_ animated: Bool) {

        super.viewWillAppear(animated)
        self.loadCurrentAccount()
    }
    
    @objc func appCameToForeGround(notification: Notification) {
        self.loadCurrentAccount()
    }
}


// MARK: Initialization

extension ViewController {
    
    /**
     
     Initialize a MSALPublicClientApplication with a given clientID and authority
     
     - clientId:            The clientID of your application, you should get this from the app portal.
     - redirectUri:         A redirect URI of your application, you should get this from the app portal.
     If nil, MSAL will create one by default. i.e./ msauth.<bundleID>://auth
     - authority:           A URL indicating a directory that MSAL can use to obtain tokens. In Azure AD
     it is of the form https://<instance/<tenant>, where <instance> is the
     directory host (e.g. https://login.microsoftonline.com) and <tenant> is a
     identifier within the directory itself (e.g. a domain associated to the
     tenant, such as contoso.onmicrosoft.com, or the GUID representing the
     TenantID property of the directory)
     - error                The error that occurred creating the application object, if any, if you're
     not interested in the specific error pass in nil.
     */
    func initMSAL() throws {
        
        let siginPolicyAuthority = try self.getAuthority(forPolicy: self.kSignupOrSigninPolicy)
        let editProfileAuthority = try self.getAuthority(forPolicy: self.kEditProfilePolicy)
        
        let pcaConfig = MSALPublicClientApplicationConfig(clientId: kClientID, redirectUri: kRedirectUri, authority: siginPolicyAuthority)
        
        pcaConfig.knownAuthorities = [siginPolicyAuthority, editProfileAuthority]
        self.applicationContext = try MSALPublicClientApplication(configuration: pcaConfig)
        
        self.initWebViewParams()
    }
    
    func initWebViewParams() {
        self.webViewParamaters = MSALWebviewParameters(authPresentationViewController: self)
    }
}

// MARK: Shared device

extension ViewController {
    
    @objc func getDeviceMode(_ sender: UIButton) {
                
        if #available(iOS 13.0, *) {
            self.applicationContext?.getDeviceInformation(with: nil, completionBlock: { (deviceInformation, error) in
                
                guard let deviceInfo = deviceInformation else {
                    self.updateLogging(text: "Device info not returned. Error: \(String(describing: error))")
                    return
                }
                
                let isSharedDevice = deviceInfo.deviceMode == .shared
                let modeString = isSharedDevice ? "shared" : "private"
                self.updateLogging(text: "Received device info. Device is in the \(modeString) mode.")
            })
        } else {
            self.updateLogging(text: "Running on older iOS. GetDeviceInformation API is unavailable.")
        }
    }
}


// MARK: Acquiring and using token

extension ViewController {
    
    /**
     This will invoke the authorization flow.
     */
    
    @objc func callGraphAPI(_ sender: UIButton) {
        
        self.loadCurrentAccount { (account) in
            
            guard let currentAccount = account else {
                
                // We check to see if we have a current logged in account.
                // If we don't, then we need to sign someone in.
                self.acquireTokenInteractively()
                return
            }
            
            self.acquireTokenSilently(currentAccount)
        }
    }
    
    func acquireTokenInteractively() {
        do
        {
            guard let applicationContext = self.applicationContext else { return }
//            guard let webViewParameters = self.webViewParamaters else { return }

            let authority = try self.getAuthority(forPolicy: self.kSignupOrSigninPolicy)
            
            let myParentController: UIViewController = self
            let webViewParameters = MSALWebviewParameters(authPresentationViewController: myParentController)
            webViewParameters.webviewType = MSALWebviewType.authenticationSession
            let interactiveParameters = MSALInteractiveTokenParameters(scopes: kScopes, webviewParameters: webViewParameters)
                        
            interactiveParameters.authority = authority
            interactiveParameters.promptType = .promptIfNecessary
            
            applicationContext.acquireToken(with: interactiveParameters) { (result, error) in
                
                if let error = error {
                    
                    self.updateLogging(text: "Could not acquire token: \(error)")
                    return
                }
                
                guard let result = result else {
                    
                    self.updateLogging(text: "Could not acquire token: No result returned")
                    return
                }
                
                self.accessToken = result.accessToken
                self.updateLogging(text: "Access token is \(self.accessToken)")
                self.updateCurrentAccount(account: result.account as! MSALAccount)
                                
//                if let value = self.keychain.get("account") {
//                  print(value)
//                } else {
//                  print("Nothing")
//                }
//                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.account, options: JSONSerialization.WritingOptions.prettyPrinted) else {
//                    
//                    self.updateLogging(text: "Couldn't deserialize result JSON")
//                    return
//                }
                
//                guard let JSONObject = try? JSONSerialization.jsonObject(with: result.account, options: <#T##JSONSerialization.ReadingOptions#>) else {
//                    self.updateLogging(text: "Couldn't deserialize result JSON")
//                    return
//                }
//                let data =  try! JSONSerialization.data(withJSONObject: JSONObject, options: [])
//                print(result.account.username! + "-" + result.account.identifier!)
//                var data: Data? = NSKeyedArchiver.archivedData(withRootObject: result.account)
                self.keychain.set(result.account.identifier!, forKey: "accountIdentifier")
                //self.getContentWithToken()
            }
        }
        catch {
            self.updateLogging(text: "Unable to create authority \(error)")
        }
    }
    
    func acquireTokenSilently(_ account : MSALAccount!) {
        
        guard let applicationContext = self.applicationContext else { return }
        guard let authority = try? self.getAuthority(forPolicy: self.kSignupOrSigninPolicy) else { return }
        let parameters = MSALSilentTokenParameters(scopes: kScopes, account: account)
        parameters.authority = authority

        applicationContext.acquireTokenSilent(with: parameters) { (result, error) in
            
            if let error = error {
                
                let nsError = error as NSError
                
                // interactionRequired means we need to ask the user to sign-in. This usually happens
                // when the user's Refresh Token is expired or if the user has changed their password
                // among other possible reasons.
                
                if (nsError.domain == MSALErrorDomain) {
                    
                    if (nsError.code == MSALError.interactionRequired.rawValue) {
                        
                        DispatchQueue.main.async {
                            self.acquireTokenInteractively()
                        }
                        return
                    }
                }
                
                self.updateLogging(text: "Could not acquire token silently: \(error)")
                return
            }
            
            guard let result = result else {
                
                self.updateLogging(text: "Could not acquire token: No result returned")
                return
            }
            
//            guard let jsonData = try? JSONSerialization.data(w: result.account, options: JSONSerialization.WritingOptions.prettyPrinted) else {
//
//                self.updateLogging(text: "Couldn't deserialize result JSON")
//                return
//            }
            
//            let data = result.account
//            self.keychain.set(result.account.identifier!, forKey: self.keyChainAccountIdentifierName)
//            let defaults = UserDefaults.standard
//            defaults.set(result.account, forKey: "accounts")
            let data = result.account.dictionaryWithValues(forKeys: ["username", "accountClaims", "identifier", "environment"])
//            data.accountClaims = Dictionary<String, String>()
//            data.identifier = result.account.identifier
//            data.username = result.account.username
//            result.account.tenantProfiles
//            result.account.accountClaims?.forEach {
//                data.accountClaims?[$0] = $1 as? String
//            }
//            do {
//                let nsJson = try? JSONSerialization.jsonObject(with: result!, options:[])
//                let json = JSON(nsJson) // Woohoo!! It works!!
//            } catch {
//                print("Error")
//            }
            let json = JSON(data)
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: JSONSerialization.WritingOptions.prettyPrinted) else {
                return
            }
//
//
            self.keychain.set(jsonData, forKey: self.keyChainAccountIdentifierName)
            self.accessToken = result.accessToken
            self.updateLogging(text: "Refreshed Access token is \(self.accessToken)")
            self.updateSignOutButton(enabled: true)
            //self.getContentWithToken()
        }
    }
    
    func getGraphEndpoint() -> String {
        return kGraphEndpoint.hasSuffix("/") ? (kGraphEndpoint + "v1.0/me/") : (kGraphEndpoint + "/v1.0/me/");
    }
    
    /**
     This will invoke the call to the Microsoft Graph API. It uses the
     built in URLSession to create a connection.
     */
    
    func getContentWithToken() {
        
        // Specify the Graph API endpoint
        let graphURI = getGraphEndpoint()
        let url = URL(string: graphURI)
        var request = URLRequest(url: url!)
        
        // Set the Authorization header for the request. We use Bearer tokens, so we specify Bearer + the token we got from the result
        request.setValue("Bearer \(self.accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                self.updateLogging(text: "Couldn't get graph result: \(error)")
                return
            }
            
            guard let result = try? JSONSerialization.jsonObject(with: data!, options: []) else {
                
                self.updateLogging(text: "Couldn't deserialize result JSON")
                return
            }
            
            self.updateLogging(text: "Result from Graph: \(result))")
            
            }.resume()
    }

}


// MARK: Get account and removing cache

extension ViewController {
    
    typealias AccountCompletion = (MSALAccount?) -> Void
    
    func loadCurrentAccount(completion: AccountCompletion? = nil) {
        do
        {
            guard let applicationContext = self.applicationContext else { return }
            
            let jsonData = self.keychain.get(self.keyChainAccountIdentifierName)
//            if let data = jsonData?.data(using: .utf8) {
//                let json = try? JSON(data: data)
////                let rawObject: MSALAccount = json?.object as! MSALAccount
////                print(rawObject)
//                let accounts = try? applicationContext.allAccounts()
//                print(accounts)
//                var data: Data? = NSKeyedArchiver.archivedData(withRootObject: accounts![0])
//            }
//            let authority = try self.getAuthority(forPolicy: self.kEditProfilePolicy)
//
//            let thisAccount = try self.getAccountByPolicy(withAccounts: application.allAccounts(), policy: kEditProfilePolicy)
            let accounts = try? applicationContext.allAccounts();
            let msalParameters = MSALParameters()
            msalParameters.completionBlockQueue = DispatchQueue.main
                    
            // Note that this sample showcases an app that signs in a single account at a time
            // If you're building a more complex app that signs in multiple accounts at the same time, you'll need to use a different account retrieval API that specifies account identifier
            // For example, see "accountsFromDeviceForParameters:completionBlock:" - https://azuread.github.io/microsoft-authentication-library-for-objc/Classes/MSALPublicClientApplication.html#/c:objc(cs)MSALPublicClientApplication(im)accountsFromDeviceForParameters:completionBlock:
            applicationContext.getCurrentAccount(with: msalParameters, completionBlock: { (currentAccount, previousAccount, error) in
                
                if let error = error {
                    self.updateLogging(text: "Couldn't query current account with error: \(error)")
                    return
                }
                
                if let currentAccount = currentAccount {
                    
                    self.updateLogging(text: "Found a signed in account \(String(describing: currentAccount.username)). Updating data for that account...")
                    
                    self.updateCurrentAccount(account: currentAccount as! MSALAccount)
                    
                    if let completion = completion {
                        completion(self.currentAccount)
                    }
                    
                    return
                }
                         
                
                var message = "Account signed out. Updating UX. Identifier in Keychain: "
                if let accountIdentifier = self.keychain.get(self.keyChainAccountIdentifierName) {
                    message += accountIdentifier
//                    guard let authority = try? self.getAuthority(forPolicy: self.kSignupOrSigninPolicy) else { return }
                    
//                    let parameters = MSALAccountEnumerationParameters(identifier:accountIdentifier)
//
//                    if #available(iOS 13.0, macOS 10.15, *)
//                    {
//                        applicationContext.accountsFromDevice(for: parameters, completionBlock:{(accounts, accError) in
//                             if let accError = accError
//                             {
//                                self.updateLogging(text: "Couldn't query current account with error: \(accError)")
//                                return
//                             }
//                            guard let accountObjs = accounts else { return }
//                            if( accounts?.count == 0 ) { return }
//                            self.updateCurrentAccount(account: accountObjs[0])
//                            if let completion = completion {
//                                completion(self.currentAccount)
//                            }
//
//                            return
//                       })
//
//                    }
                    if let account = try? applicationContext.account(forIdentifier: accountIdentifier) {
                        self.updateCurrentAccount(account: account as! MSALAccount)
                        if let completion = completion {
                            completion(self.currentAccount)
                        }
                        return
                    }
                } else {
                  print("Nothing")
                }
                
                self.updateLogging(text: message)
                self.accessToken = ""
                self.updateCurrentAccount(account: nil)
                
                if let completion = completion {
                    completion(nil)
                }
            })
        }
        catch {
            self.updateLogging(text: "Unable to construct parameters before calling acquire token \(error)")
        }
    }
    
    /**
     This action will invoke the remove account APIs to clear the token cache
     to sign out a user from this application.
     */
    @objc func signOut(_ sender: UIButton) {
        
        guard let applicationContext = self.applicationContext else { return }
        
        guard let account = self.currentAccount else { return }
        
        do {
            
            /**
             Removes all tokens from the cache for this application for the provided account
             
             - account:    The account to remove from the cache
             */
            
            let signoutParameters = MSALSignoutParameters(webviewParameters: self.webViewParamaters!)
            signoutParameters.signoutFromBrowser = false
            
            applicationContext.signout(with: account, signoutParameters: signoutParameters, completionBlock: {(success, error) in
                
                if let error = error {
                    self.updateLogging(text: "Couldn't sign out account with error: \(error)")
                    return
                }
                
                self.updateLogging(text: "Sign out completed successfully")
                self.accessToken = ""
                self.updateCurrentAccount(account: nil)
            })
            
        }
    }
}


// MARK: UI Helpers
extension ViewController {
    
    func initUI() {
        
        usernameLabel = UILabel()
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.text = ""
        usernameLabel.textColor = .darkGray
        usernameLabel.textAlignment = .right
        
        self.view.addSubview(usernameLabel)
        
        usernameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 50.0).isActive = true
        usernameLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -10.0).isActive = true
        usernameLabel.widthAnchor.constraint(equalToConstant: 300.0).isActive = true
        usernameLabel.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        
        // Add call Graph button
        callGraphButton  = UIButton()
        callGraphButton.translatesAutoresizingMaskIntoConstraints = false
        callGraphButton.setTitle("Authorize", for: .normal)
        callGraphButton.setTitleColor(.blue, for: .normal)
        callGraphButton.addTarget(self, action: #selector(callGraphAPI(_:)), for: .touchUpInside)
        self.view.addSubview(callGraphButton)
        
        callGraphButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        callGraphButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 120.0).isActive = true
        callGraphButton.widthAnchor.constraint(equalToConstant: 300.0).isActive = true
        callGraphButton.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        
        // Add sign out button
        signOutButton = UIButton()
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.setTitle("Sign Out", for: .normal)
        signOutButton.setTitleColor(.blue, for: .normal)
        signOutButton.setTitleColor(.gray, for: .disabled)
        signOutButton.addTarget(self, action: #selector(signOut(_:)), for: .touchUpInside)
        self.view.addSubview(signOutButton)
        
        signOutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        signOutButton.topAnchor.constraint(equalTo: callGraphButton.bottomAnchor, constant: 10.0).isActive = true
        signOutButton.widthAnchor.constraint(equalToConstant: 150.0).isActive = true
        signOutButton.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        
        let deviceModeButton = UIButton()
        deviceModeButton.translatesAutoresizingMaskIntoConstraints = false
        deviceModeButton.setTitle("Get device info", for: .normal);
        deviceModeButton.setTitleColor(.blue, for: .normal);
        deviceModeButton.addTarget(self, action: #selector(getDeviceMode(_:)), for: .touchUpInside)
        self.view.addSubview(deviceModeButton)
        
        deviceModeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        deviceModeButton.topAnchor.constraint(equalTo: signOutButton.bottomAnchor, constant: 10.0).isActive = true
        deviceModeButton.widthAnchor.constraint(equalToConstant: 150.0).isActive = true
        deviceModeButton.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        
        // Add logging textfield
        loggingText = UITextView()
        loggingText.isUserInteractionEnabled = true
        loggingText.translatesAutoresizingMaskIntoConstraints = false
        
        self.view.addSubview(loggingText)
        
        loggingText.topAnchor.constraint(equalTo: deviceModeButton.bottomAnchor, constant: 10.0).isActive = true
        loggingText.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: 10.0).isActive = true
        loggingText.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: -10.0).isActive = true
        loggingText.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: 10.0).isActive = true
    }
    
    func updateLogging(text : String) {
        
        if Thread.isMainThread {
            self.loggingText.text = text
        } else {
            DispatchQueue.main.async {
                self.loggingText.text = text
            }
        }
    }
    
    func updateSignOutButton(enabled : Bool) {
        if Thread.isMainThread {
            self.signOutButton.isEnabled = enabled
        } else {
            DispatchQueue.main.async {
                self.signOutButton.isEnabled = enabled
            }
        }
    }
    
    func updateAccountLabel() {
        
        guard let currentAccount = self.currentAccount else {
            self.usernameLabel.text = "Signed out"
            return
        }
        
        self.usernameLabel.text = currentAccount.username
    }
    
    func updateCurrentAccount(account: MSALAccount?) {
        self.currentAccount = account
        self.updateAccountLabel()
        self.updateSignOutButton(enabled: account != nil)
    }
    
    func getAuthority(forPolicy policy: String) throws -> MSALB2CAuthority {
        let url = String(format: self.kEndpoint, self.kAuthorityHostName, self.kTenantName, policy)
        guard let authorityURL = URL(string: url) else {
            throw NSError(domain: "SomeDomain",
                          code: 1,
                          userInfo: ["errorDescription": "Unable to create authority URL!"])
        }
        return try MSALB2CAuthority(url: authorityURL)
    }
}
