//
//  JakeyURLProtocol.h
//  NSURLProtocolExample
//
//  Created by Jake on 2017/7/10.
//  Copyright © 2017年 Rocir Santiago. All rights reserved.
//

#import <Foundation/Foundation.h>
typedef NS_ENUM(NSUInteger, CacheStatus) {
    OutOfDate = 0,
    UpdateNeeded  = 1,
    UpdateNeedLess = 2,
};

@interface JakeyURLProtocol : NSURLProtocol

@end

@interface YJCachedResponse : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) NSString *url;
@property (nonatomic, strong) NSString *mimeType;
@property (nonatomic, strong) NSString *encoding;
@property (nonatomic, strong, readonly) NSURLResponse *response;

/**
 初始化封装的YJResponse对象
 
 @param data 请求结果数据
 @param response
 @param timeInterval 缓存过期时间
 @return 封装的YJResponse对象
 */
- (instancetype)initWithData:(NSData *)data response:(NSURLResponse *)response limiteTime:(NSTimeInterval)timeInterval;

//检查缓存是否过期 0 ：已过期 ,   1 ： 需更新缓存,   2 ：无需更新缓存
- (CacheStatus)isCacheEffective;

@end
