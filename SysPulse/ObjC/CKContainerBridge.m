#import "CKContainerBridge.h"

CKContainer * _Nullable SysPulseSafeCKContainer(NSString *identifier) {
    @try {
        return [CKContainer containerWithIdentifier:identifier];
    } @catch (NSException *exception) {
        NSLog(@"[SysPulse] CKContainer init failed for '%@': %@ — %@",
              identifier, exception.name, exception.reason);
        return nil;
    }
}
