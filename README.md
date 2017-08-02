# YJURLProtocol

使用NSURLProtocol子类实现UIWebView缓存机制，支持缓存过期时间设置，异步更新缓存

### 介绍

|功能|支持|说明|
|:-:|:-:|:-:|
|缓存数据|是|将整个request缓存下来，以及其response|
|设置过期时间|是|默认为两天过期，过期后请求会删除原有缓存|
|自动更新缓存|是|间隔时间超过1min的请求，加载页面后异步更新缓存|

UIWebView缓存使用机制：

* 两个相同的请求时间相隔在60s之内，直接使用缓存，不进行异步更新缓存
* 两个相同的请求相隔60s+但是没有过期，使用缓存加载页面后，1min后进行异步更新缓存并刷新页面
* 缓存命中但是时间已经是两天前，则删除缓存走网络数据

<!--more-->

## NSURLProtocol
### 什么是NSURLPrototol （[NSURLProtocol什么的我都懂，我要直接看🌰](#example)）
Apple的[URL Loading System](https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html#//apple_ref/doc/uid/10000165-BCICJDHA)的核心是`NSURL`类，`NSURL`提供给app要访问资源的地址，`NSURLRequest`对象再额外添加HTTP headers， body之类的信息，然后`URL Loading System`提供`NSURLSession`和`NSURLConnection`的各种子类方法去执行这个请求。

请求返回的数据会有两分部分，metadata 和 data。metadata被包括在`NSURLResponse`对象中，它会提供MIME type，和 text encoding。 data的数据是NSData类型。

在以上过程之后，URL Loading System通过NSURLRequest下载了信息之后，它将会创建一个NSURLProtocol子类的对象。

>Note: Remember that Objective-C doesn’t actually have abstract classes as a first class citizen. It’s only by definition and documentation that a class is marked as abstract.

千万不能直接实例化NSURLProtocol, 必须要继承NSURLProtocol,在子类中创建NSURLResponse处理response。

### 使用NSURLProtocol能做什么
* 为网络请求提供自定义的Response

	可以在网络调试的时候，发起网络请求后进行自定义返回数据调试自己的APP 
 
* 调过网络请求，加载本地数据

	某些情况下，发起的请求并没有去请求网络的必要，可以修改使用本地的数据。（自定义webView的缓存就是如此实现）
	
* 重定向网络请求

	可以将请求重定向到某个代理服务器，不需要通过iOS给用户弹出授权窗口

* 修改Request的User-agent

	如果你的一个页面是分不同的设备返回数据的，那么可以在这里设置自定的user-agent，来达到你的需求。

* 使用自己的网络协议

	可以替换使用自己实现的网络协议，比如有些建立在UDP之上的协议。

### NSURLProtocol的使用

``` objectivec
[NSURLProtocol registerClass:[JakeyURLProtocol class]];
```
以上代码表示，你已经向URL Loading System注册了自己的NSURLProtocol子类，这个子类将有机会处理每一个发送到URL Loading System的请求。


#### 在NSURLProtocol的子类实现文件中：

``` objectivec
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return YES;
}
```
重载以上代码，返回YES。表示此子类注册之后将使用此子类处理所有的请求，返回NO则仍然使用URL Loading System的默认protocol处理请求。


``` objectivec
//这是个抽象方法，子类必须提供实现方法。此方法可用于修改request，添加一个header等
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

//用于判断你的自定义reqeust是否相同，这里返回默认实现即可。它的主要应用场景是某些直接使用缓存而非再次请求网络的地方。
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

//开始请求
- (void)startLoading {
    self.connection = [NSURLConnection connectionWithRequest:self.request delegate:self];
}

//请求结束
- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}

```

## <span id = example>自定义NSURLProtocol实现UIWebView缓存机制</span>

开始请求之后，将此请求标记为已处理

``` objectivec
- (void)startLoading {
	NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:newRequest];
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
}

```

判断请求是否已经被处理过，避免循环被处理

``` objectivec
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

```

自定义YJCacheResponse对象，内容包含内容如下代码

``` objectivec
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
```


在开始请求`- (void)startLoading`方法中，判断是走缓存还是使用网络请求数据

``` objectivec

- (void)startLoading {
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    self.cachedFilePath = [docPath stringByAppendingPathComponent:md5(self.request.URL.absoluteString)];
    //在缓存表中获取当前request是否有缓存
    YJCachedResponse *cachedResponse = [self cachedResponseForCurrentRequest];
    if (cachedResponse) {
        switch ([cachedResponse isCacheEffective]) {
            case OutOfDate:
                [self useNetData];
                break;
            case UpdateNeedLess: 
                [self useCacheData:cachedResponse];
                break;
            case UpdateNeeded: 
                [self useCacheData:cachedResponse];
                //1秒钟之后重新请求，更新缓存
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self useNetData];
                });
                break;
            default:
                break;
        }
    } else {
        [self useNetData];
    }
}

```

在NSURLConnectionDelegate方法中进行Response保存和赋值

``` objectivec

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

```


#### 以上只列出部分关键逻辑代码，详细实现请下载[demo](https://github.com/HuyangJake/YJURLProtocol)查看源码

### 问题缺陷
* 一个网站会有些网络请求地址跟时间戳或者其他随机字符相关，缓存机制会缓存下来，并且之后一直没有机会命中它们，没有办法自动删除这些缓存，会造成内存浪费。

因本人水平有限，文中有什么不正确之处，还请指出，不胜感谢！

### Reference 
[https://www.raywenderlich.com/59982/nsurlprotocol-tutorial](https://www.raywenderlich.com/59982/nsurlprotocol-tutorial)
