//
//  JakeyURLProtocol.m
//  NSURLProtocolExample
//
//  Created by Jake on 2017/7/10.
//  Copyright © 2017年 Rocir Santiago. All rights reserved.
//

#import "JakeyURLProtocol.h"
#import "objc/runtime.h"
#import<CommonCrypto/CommonDigest.h>

static NSString * const kHandledKey = @"HandledKey";
static NSInteger const kLimiteTime = 3600*24*2;//缓存有效时间(秒)
NSString * md5(NSString *);//md5转化函数

@interface JakeyURLProtocol ()<NSURLConnectionDelegate>
@property (nonatomic, strong) NSURLConnection *connection;

@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, strong) NSMutableData *mutableData;

@property (nonatomic, strong) NSString *cachedFilePath;
@end

@implementation JakeyURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = request.URL.scheme;
    if ([scheme caseInsensitiveCompare:@"http"]==NSOrderedSame||[scheme caseInsensitiveCompare:@"https"]==NSOrderedSame) {
        if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void)startLoading {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    self.cachedFilePath = [docPath stringByAppendingPathComponent:md5(self.request.URL.absoluteString)];
    
    YJCachedResponse *cachedResponse = [self cachedResponseForCurrentRequest];
    if (cachedResponse) {
        switch ([cachedResponse isCacheEffective]) {
            case OutOfDate:{
                [self useNetData];
            }
                break;
            case UpdateNeedLess: {
                [self useCacheData:cachedResponse];
            }
                break;
            case UpdateNeeded: {
                [self useCacheData:cachedResponse];
                //1秒钟之后重新请求，更新缓存
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self useNetData];
                });
            }
                break;
            default:
                break;
        }
    } else {
        [self useNetData];
    }
}

- (void)useCacheData:(YJCachedResponse *)cachedResponse {
    NSLog(@"走缓存, %@", md5(self.request.URL.absoluteString));
    [self.client URLProtocol:self didReceiveResponse:cachedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:cachedResponse.data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)useNetData {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:newRequest];
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
}

- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    
    self.response = response;
    self.mutableData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
    [self.mutableData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
    [self saveCachedResponse];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
    
}

#pragma mark - Custom Actions

- (void)saveCachedResponse {
    YJCachedResponse *response = [[YJCachedResponse alloc] initWithData:self.mutableData response:self.response limiteTime:kLimiteTime];
    NSMutableData *muData = [NSMutableData dataWithData:[NSKeyedArchiver archivedDataWithRootObject:response]];
    BOOL isSuccess = [muData writeToFile:self.cachedFilePath atomically:YES];
//    BOOL isSuccess = [NSKeyedArchiver archiveRootObject:response toFile:self.cachedFilePath];
    NSLog(@"%@  archive success %d", md5(response.url),  isSuccess);
}

- (YJCachedResponse *)cachedResponseForCurrentRequest {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.cachedFilePath]) {
        return nil;
    }
    YJCachedResponse *response = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:self.cachedFilePath]];
//    YJCachedResponse *response = [NSKeyedUnarchiver unarchiveObjectWithFile:self.cachedFilePath];
    return response;
}

@end

NSString * md5(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), digest );
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return output;
}

@interface YJCachedResponse()<NSCoding>
@property (nonatomic, assign) NSTimeInterval timeInterval;
@property (nonatomic, strong) NSDate *cachedTime;
@property (nonatomic, strong) NSString *cachedFilePath;

@property (nonatomic, strong, readwrite) NSURLResponse *response;
@end

@implementation YJCachedResponse

- (instancetype)initWithData:(NSData *)data response:(NSURLResponse *)response limiteTime:(NSTimeInterval)timeInterval{
    self = [super init];
    if (self) {
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        self.cachedFilePath = [docPath stringByAppendingPathComponent: md5(response.URL.absoluteString)];
        
        self.data = [data copy];
        self.url = [response.URL.absoluteString copy];
        self.cachedTime = [NSDate date];
        self.mimeType = [response.MIMEType copy];
        self.encoding = [response.textEncodingName copy];
        self.timeInterval = timeInterval;
        
        self.response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:self.url] MIMEType:self.mimeType expectedContentLength:self.data.length textEncodingName:self.encoding];
    }
    return self;
}


- (CacheStatus)isCacheEffective {
    //检查是否过期,已失效则删除缓存
    if ( [[NSDate date]timeIntervalSinceDate:self.cachedTime] > self.timeInterval) {//超出过期时间
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.cachedFilePath]) {
            NSLog(@"缓存不存在？！！！, %@", md5(self.url));
            return OutOfDate;
        }
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.cachedFilePath error:&error];
        if (!error) {
            NSLog(@"缓存过期，已删除, %@", md5(self.url));
        } else {
            NSLog(@"缓存删除失败, %@", md5(self.url));
        }
        return OutOfDate;
    } else if ([[NSDate date]timeIntervalSinceDate:self.cachedTime] <= 60) {//距离上一次加载没到一分钟，无需更新缓存
        return UpdateNeedLess;
    } else {//距离上一次加载超过一分钟，先加载缓存，后台再更新缓存
        return UpdateNeeded;
    }
}

#pragma mark - 归档解档

- (void)encodeWithCoder:(NSCoder *)aCoder {
    unsigned int count ;
    objc_property_t *propertyList = class_copyPropertyList([self class], &count);
    for (unsigned int i = 0; i<count ; i++) {
        objc_property_t property = propertyList[i];
        const char *name = property_getName(property);
        NSString *properName = [NSString stringWithUTF8String:name];
        [aCoder encodeObject:[self valueForKey:properName] forKey:properName];
    }
    free(propertyList);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        unsigned int count ;
        objc_property_t *propertyList = class_copyPropertyList([self class], &count);
        for (unsigned int i = 0; i<count ; i++) {
            objc_property_t property = propertyList[i];
            const char *name = property_getName(property);
            NSString *properName = [NSString stringWithUTF8String:name];
            [self setValue:[aDecoder decodeObjectForKey:properName] forKey:properName];
        }
        free(propertyList);
    }
    return self;
}


@end
