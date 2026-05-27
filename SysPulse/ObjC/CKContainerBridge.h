#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps CKContainer(identifier:) in @try/@catch so a bad identifier or
/// missing CloudKit entitlement produces nil instead of a crash.
CKContainer * _Nullable SysPulseSafeCKContainer(NSString *identifier);

NS_ASSUME_NONNULL_END
