//
//  Purchase.swift
//  SwiftHelpSet
//
//  Created by Luca D'Alberti on 7/20/16.
//  Copyright © 2016 dalu93. All rights reserved.
//

import Foundation
import StoreKit

/// The `Purchase` object represents an elegant and functional way to use the 
/// `StoreKit` framework provided by Apple.
public final class Purchase: NSObject {
    private static let shared = Purchase()
    private var productRequest: SKRequest? {
        didSet {
            productRequest?.delegate = self
            productRequest?.start()
        }
    }
    
    private var restoreRequest: SKRequest? {
        didSet {
            restoreRequest?.delegate = self
            restoreRequest?.start()
        }
    }
    
    private var purchasing = false
    
    private var onFetchedProducts: (Completion<[SKProduct], NSError> -> ())?
    private var onPurchaseCompleted: (Completion<NSData, NSError> -> ())?
    private var onPurchaseRestored: (Completion<NSData, NSError> -> ())?
    
    // MARK: - Static methods
    
    /**
     Requests a list of `SKProduct` from an array of identifiers. 
     
     It calls the completion block
     when the request is completed or failed.
     Whenever this method is called, it cancels any other appending requests of the same type
     
     - parameter identifiers: The products identifiers list
     - parameter completion:  Completion handler
     */
    static public func productsFrom(identifiers identifiers: [String], completion: Completion<[SKProduct], NSError> -> ()) {
        Purchase.shared.onFetchedProducts = completion
        
        Purchase.shared.productRequest?.cancel()
        Purchase.shared.productRequest = SKProductsRequest(productIdentifiers: Set(identifiers))
    }
    
    /**
     Purchase a `SKProduct`. 
     
     The completion handler could return the receipt `NSData` value or
     an error
     
     - parameter product:    The product to buy
     - parameter completion: Completion handler
     */
    static public func purchase(product product: SKProduct, completion: Completion<NSData, NSError> -> ()) {
        
        guard Purchase.shared.purchasing else {
            completion(.failed(.purchaseInProgressError()))
            return
        }
        
        Purchase.shared.purchasing = true
        Purchase.shared.onPurchaseCompleted = completion
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.defaultQueue().addPayment(payment)
    }
    
    /**
     Tries to restore the purchase the account has done before. 
     
     The completion handler could return the receipt `NSData` value.
     
     - parameter completion: Completion handler
     */
    static public func restorePurchase(completion: Completion<NSData, NSError> -> ()) {
        Purchase.shared.onPurchaseRestored = completion
        Purchase.shared.restoreRequest = SKReceiptRefreshRequest()
    }
    
    // MARK: - Object lifecycle
    override public init() {
        super.init()
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
    }
    
    deinit {
        SKPaymentQueue.defaultQueue().removeTransactionObserver(self)
    }
}

// MARK: - SKProductsRequestDelegate
extension Purchase: SKProductsRequestDelegate {
    public func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {
        let products = response.products
        let invalidProductsIdentifier = response.invalidProductIdentifiers
        
        guard invalidProductsIdentifier.isEmpty else {
            onFetchedProducts?(.failed(.errorWith(invalidIdentifiers: invalidProductsIdentifier)))
            return
        }
        
        onFetchedProducts?(.success(products))
    }
}

// MARK: - SKRequestDelegate
extension Purchase: SKRequestDelegate {
    
    public func requestDidFinish(request: SKRequest) {
        
        if request == restoreRequest {
            
            guard let receipt = self._getReceipt() else {
                onPurchaseRestored?(.failed(.restoringError()))
                return
            }
            
            onPurchaseRestored?(.success(receipt))
        }
    }
}

// MARK: - SKPaymentTransactionObserver
extension Purchase: SKPaymentTransactionObserver {
    public func paymentQueue(queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        
        transactions.forEach {
            switch $0.transactionState {
            case .Purchasing, .Deferred: break
            case .Purchased:
                purchasing = false
                guard let receipt = self._getReceipt() else {
                    onPurchaseCompleted?(.failed(.purchaseGenericError()))
                    return
                }
                
                onPurchaseCompleted?(.success(receipt))
                
            case .Failed:
                purchasing = false
                onPurchaseCompleted?(.failed($0.error ?? .purchaseGenericError()))
                SKPaymentQueue.defaultQueue().finishTransaction($0)

            default:
                purchasing = false
                SKPaymentQueue.defaultQueue().finishTransaction($0)
            }
        }
    }
}

// MARK: - Receipt utility
private extension Purchase {
    func _getReceipt() -> NSData? {
        if let url = NSBundle.mainBundle().appStoreReceiptURL {
            return NSData(contentsOfURL: url)
        }
        return nil
    }
}

// MARK: - Error utilities
private extension NSError {
    static func errorWith(invalidIdentifiers invalidIdentifiers: [String]) -> NSError {
        return NSError(
            domain: "Purchase",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "The product identifiers (\(invalidIdentifiers) are invalid)"
            ]
        )
    }
    
    static func restoringError() -> NSError {
        return NSError(
            domain: "Purchase",
            code: -2,
            userInfo: [
                NSLocalizedDescriptionKey: "Error while restoring the purchases"
            ]
        )
    }
    
    static func purchaseGenericError() -> NSError {
        return NSError(
            domain: "Purchase",
            code: -3,
            userInfo: [
                NSLocalizedDescriptionKey: "Error while purchasing"
            ]
        )
    }
    
    static func purchaseInProgressError() -> NSError {
        return NSError(
            domain: "Purchase",
            code: -4,
            userInfo: [
                NSLocalizedDescriptionKey: "An another pruchase is still processing"
            ]
        )
    }
}