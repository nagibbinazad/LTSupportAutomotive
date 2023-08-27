//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LTBTLESerialTransporterScanDelegate <NSObject>

- (void)didFoundPeripherals:(nullable NSArray<CBPeripheral *> *)peripherals;

@end

extern NSString* const LTBTLESerialTransporterDidUpdateSignalStrength;

typedef void(^LTBTLESerialTransporterConnectionBlock)(NSInputStream* _Nullable inputStream, NSOutputStream* _Nullable outputStream, NSError* _Nullable error);
typedef void(^LTBTLESerialTransporterDisconnectBlock)(BOOL isDisconnected, NSError* _Nullable error);

@interface LTBTLESerialTransporter : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>

@property(strong,nonatomic,readonly) NSNumber* signalStrength;
@property(assign, nonatomic) id<LTBTLESerialTransporterScanDelegate> delegate;
@property(assign, nonatomic) BOOL isConnected;

+(instancetype)transporterWithIdentifier:(nullable NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs;
-(void)startScanning:(id<LTBTLESerialTransporterScanDelegate>)delegate;
-(void)stopScanning;
-(void)connect:(nonnull CBPeripheral *) peripheral withConnectionBlock:(LTBTLESerialTransporterConnectionBlock)block;
-(void)disconnect:(nonnull CBPeripheral *)peripheral withCompletionBlock:(nullable LTBTLESerialTransporterDisconnectBlock)block;

-(void)startUpdatingSignalStrengthWithInterval:(NSTimeInterval)interval;
-(void)stopUpdatingSignalStrength;

@end

NS_ASSUME_NONNULL_END

