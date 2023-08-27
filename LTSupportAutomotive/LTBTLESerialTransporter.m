//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//

#import "LTBTLESerialTransporter.h"

#import "LTSupportAutomotive.h"

#import "LTBTLEReadCharacteristicStream.h"
#import "LTBTLEWriteCharacteristicStream.h"

NSString* const LTBTLESerialTransporterDidUpdateSignalStrength = @"LTBTLESerialTransporterDidUpdateSignalStrength";

//#define DEBUG_THIS_FILE

#ifdef DEBUG_THIS_FILE
    #define XLOG LOG
#else
    #define XLOG(...)
#endif

@implementation LTBTLESerialTransporter
{
    CBCentralManager* _manager;
    NSUUID* _identifier;
    NSArray<CBUUID*>* _serviceUUIDs;
    CBPeripheral* _selectedAdapter;
    CBCharacteristic* _reader;
    CBCharacteristic* _writer;
    
    NSMutableArray<CBPeripheral*>* _possibleAdapters;
    
    dispatch_queue_t _dispatchQueue;
    
    LTBTLESerialTransporterConnectionBlock _connectionBlock;
    LTBTLESerialTransporterDisconnectBlock _disconnectBlock;

    LTBTLEReadCharacteristicStream* _inputStream;
    LTBTLEWriteCharacteristicStream* _outputStream;
    
    NSNumber* _signalStrength;
    NSTimer* _signalStrengthUpdateTimer;
}

#pragma mark -
#pragma mark Lifecycle

+(instancetype)transporterWithIdentifier:(NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs
{
    return [[self alloc] initWithIdentifier:identifier serviceUUIDs:serviceUUIDs];
}

-(instancetype)initWithIdentifier:(NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs
{
    if ( ! ( self = [super init] ) )
    {
        return nil;
    }
    
    _identifier = identifier;
    _serviceUUIDs = serviceUUIDs;
    
    _dispatchQueue = dispatch_queue_create( [NSStringFromClass(self.class) UTF8String], DISPATCH_QUEUE_SERIAL );
    _possibleAdapters = [NSMutableArray array];
    
    XLOG( @"Created w/ identifier %@, services %@", _identifier, _serviceUUIDs );
    
    return self;
}

-(void)dealloc
{
    [self disconnect:_selectedAdapter withCompletionBlock:nil];
}

#pragma mark -
#pragma mark API

-(void)startScanning:(id<LTBTLESerialTransporterScanDelegate>)delegate {
    self.delegate = delegate;
    [_possibleAdapters removeAllObjects];
    _manager = [[CBCentralManager alloc] initWithDelegate:self queue:_dispatchQueue options:nil];
}

-(void)stopScanning {
    if(_manager.isScanning == YES) {
        [_manager stopScan];
    }
}

-(void)connect:(nonnull CBPeripheral *) peripheral withConnectionBlock:(LTBTLESerialTransporterConnectionBlock)block;
{
    _connectionBlock = block;
    if(self.isConnected == YES) {
        [self disconnect];
    }
    self.isConnected = NO;
    
    _selectedAdapter = peripheral;
    _selectedAdapter.delegate = self;
    LOG( @"Started connecting to %@", _selectedAdapter );
    [_manager connectPeripheral:_selectedAdapter options:nil];
}

-(void)disconnect:(nonnull CBPeripheral *)peripheral withCompletionBlock:(nullable LTBTLESerialTransporterDisconnectBlock)block
{
    _disconnectBlock = block;
    [_manager cancelPeripheralConnection:peripheral];
    [self disconnect];
}

-(void)startUpdatingSignalStrengthWithInterval:(NSTimeInterval)interval
{
    [self stopUpdatingSignalStrength];
    
    _signalStrengthUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(onSignalStrengthUpdateTimerFired:) userInfo:nil repeats:YES];
}

-(void)stopUpdatingSignalStrength
{
    [_signalStrengthUpdateTimer invalidate];
    _signalStrengthUpdateTimer = nil;
}

#pragma mark -
#pragma mark NSTimer

-(void)onSignalStrengthUpdateTimerFired:(NSTimer*)timer
{
    if (_selectedAdapter == nil || _selectedAdapter.state != CBPeripheralStateConnected )
    {
        return;
    }
    
    [_selectedAdapter readRSSI];
}

#pragma mark -
#pragma mark <CBCentralManagerDelegate>

-(void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if ( central.state != CBCentralManagerStatePoweredOn )
    {
        return;
    }
    NSArray<CBPeripheral*>* peripherals = [_manager retrieveConnectedPeripheralsWithServices:_serviceUUIDs];
    if ( peripherals.count && _selectedAdapter != nil)
    {
        LOG( @"CONNECTED (already) %@", _selectedAdapter );
        if ( _selectedAdapter.state == CBPeripheralStateConnected )
        {
            _selectedAdapter = peripherals.firstObject;
            _selectedAdapter.delegate = self;
            [self peripheral:_selectedAdapter didDiscoverServices:nil];
        }
        else
        {
            [_possibleAdapters addObject:peripherals.firstObject];
            [self centralManager:central didDiscoverPeripheral:peripherals.firstObject advertisementData:@{} RSSI:@127];
        }
        return;
    }
    
    if ( _identifier )
    {
        peripherals = [_manager retrievePeripheralsWithIdentifiers:@[_identifier]];
    }
    if ( !peripherals.count )
    {
        // some devices are not advertising the service ID, hence we need to scan for all services
        [_manager scanForPeripheralsWithServices:nil options:nil];
        return;
    }
}

-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral*)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    
    LOG( @"DISCOVER %@ (RSSI=%@) w/ advertisement %@", peripheral, RSSI, advertisementData );
    [_possibleAdapters addObject:peripheral];
    if(self.delegate != nil && [self.delegate respondsToSelector:@selector(didFoundPeripherals:)]) {
        [self.delegate didFoundPeripherals:_possibleAdapters];
    }
}

-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    LOG( @"CONNECT %@", peripheral );
    [peripheral discoverServices:_serviceUUIDs];
}

-(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    LOG( @"Failed to connect %@: %@", peripheral, error );
    [self connectionAttemptFailed:error];
}

-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    LOG( @"Did disconnect %@: %@", peripheral, error );
    if (error != nil) {
        if(_disconnectBlock != nil){
            _disconnectBlock(NO, error);
            _disconnectBlock = nil;
        }
        return;
    }
    if ( peripheral == _selectedAdapter )
    {
        [_inputStream close];
        [_outputStream close];
        if(_disconnectBlock != nil){
            _disconnectBlock(YES, nil);
            _disconnectBlock = nil;
        }
    }
}

#pragma mark -
#pragma mark <CBPeripheralDelegate>

-(void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error
{
    if ( error )
    {
        LOG( @"Could not read signal strength for %@: %@", peripheral, error );
        return;
    }
    
    _signalStrength = RSSI;
    [[NSNotificationCenter defaultCenter] postNotificationName:LTBTLESerialTransporterDidUpdateSignalStrength object:self];
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if ( error )
    {
        LOG( @"Could not discover services: %@", error );
        return;
    }
    
    if ( !peripheral.services.count )
    {
        LOG( @"Peripheral does not offer requested services" );
    
        [_manager cancelPeripheralConnection:peripheral];
        [_possibleAdapters removeObject:peripheral];
        return;
    }
    
    CBService* atCommChannel = peripheral.services.firstObject;
    [peripheral discoverCharacteristics:nil forService:atCommChannel];
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    for ( CBCharacteristic* characteristic in service.characteristics )
    {
        if ( characteristic.properties & CBCharacteristicPropertyNotify )
        {
            LOG( @"Did see notify characteristic" );
            _reader = characteristic;
            
            //[peripheral readValueForCharacteristic:characteristic];
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
        
        if ( characteristic.properties & CBCharacteristicPropertyWrite )
        {
            LOG( @"Did see write characteristic" );
            _writer = characteristic;
        }
    }
    
    if ( _reader && _writer )
    {
        [self connectionAttemptSucceeded];
    }
    else
    {
        [self connectionAttemptFailed:[NSError errorWithDomain:@"com.bluetooth.scan" code:101 userInfo:@{NSLocalizedDescriptionKey : @"Not a valid OBD2 device."}]];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
#ifdef DEBUG_THIS_FILE
    NSString* debugString = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    NSString* replacedWhitespace = [[debugString stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    XLOG( @"%@ >>> %@", peripheral, replacedWhitespace );
#endif
    
    if ( error )
    {
        LOG( @"Could not update value for characteristic %@: %@", characteristic, error );
        return;
    }
    
    [_inputStream characteristicDidUpdateValue];
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if ( error )
    {
        LOG( @"Could not write to characteristic %@: %@", characteristic, error );
        return;
    }
    
    [_outputStream characteristicDidWriteValue];
}

#pragma mark -
#pragma mark Helpers

-(void)disconnect {
    [self stopUpdatingSignalStrength];
    
    [_inputStream close];
    [_outputStream close];
    _inputStream = nil;
    _outputStream = nil;
    _reader = nil;
    _writer = nil;
    [_possibleAdapters enumerateObjectsUsingBlock:^(CBPeripheral * _Nonnull eachPeripheral, NSUInteger idx, BOOL * _Nonnull stop) {
        [self->_manager cancelPeripheralConnection:eachPeripheral];
    }];
}

-(void)connectionAttemptSucceeded
{
    self.isConnected = YES;
    _inputStream = [[LTBTLEReadCharacteristicStream alloc] initWithCharacteristic:_reader];
    _outputStream = [[LTBTLEWriteCharacteristicStream alloc] initToCharacteristic:_writer];
    _connectionBlock( _inputStream, _outputStream, nil);
    _connectionBlock = nil;
}

-(void)connectionAttemptFailed:(NSError *)error
{
    self.isConnected = NO;
    if(_connectionBlock != nil) {
        _connectionBlock( nil, nil, error);
        _connectionBlock = nil;
    }
}

@end
