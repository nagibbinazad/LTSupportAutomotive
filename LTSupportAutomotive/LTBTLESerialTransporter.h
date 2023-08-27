//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LTBTLESerialTransporterDelegate <NSObject>

- (void)didFoundPeripheral:(nullable NSArray<CBPeripheral *> *)peripherals;
- (void)didDisconnectFromPeripheral:(nonnull CBPeripheral *)peripheral;

@end

extern NSString* const LTBTLESerialTransporterDidUpdateSignalStrength;

typedef void(^LTBTLESerialTransporterConnectionBlock)(NSInputStream* _Nullable inputStream, NSOutputStream* _Nullable outputStream, NSError* _Nullable error);

@interface LTBTLESerialTransporter : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>

@property(strong,nonatomic,readonly) NSNumber* signalStrength;
@property(assign, nonatomic) id<LTBTLESerialTransporterDelegate> delegate;
@property(assign, nonatomic) BOOL isConnected;

+(instancetype)transporterWithIdentifier:(nullable NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs;
-(void)startScanning:(id<LTBTLESerialTransporterDelegate>)delegate;
-(void)stopScanning;
-(void)connect:(nonnull CBPeripheral *) peripheral withConnectionBlock:(LTBTLESerialTransporterConnectionBlock)block;
-(void)disconnect:(nonnull CBPeripheral *)peripheral;

-(void)startUpdatingSignalStrengthWithInterval:(NSTimeInterval)interval;
-(void)stopUpdatingSignalStrength;

@end

NS_ASSUME_NONNULL_END

