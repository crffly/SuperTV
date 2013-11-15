//
// Copyright 2009-2010 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "TTRequestLoader.h"

// Network
#import "TTGlobalNetwork.h"
#import "TTURLRequest.h"
#import "TTURLRequestDelegate.h"
#import "TTURLRequestQueue.h"
#import "TTURLResponse.h"

// Network (private)
#import "TTURLRequestQueueInternal.h"

// Core
#import "SHThree20Extral.h"

static const NSInteger kLoadMaxRetries = 2;

@interface TTRequestLoader()
- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSHTTPURLResponse*)response;
- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data;
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
@end


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation TTRequestLoader

@synthesize urlPath             = _urlPath;
@synthesize requests            = _requests;
@synthesize cacheKey            = _cacheKey;
@synthesize cachePolicy         = _cachePolicy;
@synthesize cacheExpirationAge  = _cacheExpirationAge;


///////////////////////////////////////////////////////////////////////////////////////////////////
- (id)initForRequest:(TTURLRequest*)request queue:(TTURLRequestQueue*)queue {
  if (self = [super init]) {
    _urlPath            = [request.urlPath copy];
    _queue              = queue;
    _cacheKey           = [request.cacheKey retain];
    _cachePolicy        = request.cachePolicy;
    _cacheExpirationAge = request.cacheExpirationAge;
    _requests           = [[NSMutableArray alloc] init];
    _retriesLeft        = kLoadMaxRetries;
    _totalLength        = 0;
      _totalCurrentLen  = 0;

      if (request.seqmentData != nil && request.breakSeqment)
      {
          _totalLength = llabs([[request.seqmentData objectForKey:kSeqmentTotalLength] longLongValue]);
          _totalCurrentLen = llabs([[request.seqmentData objectForKey:kSeqmentCurrentLength] longLongValue]);
      }
    [self addRequest:request];
  }
  return self;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
  [_connection cancel];
  TT_RELEASE_SAFELY(_connection);
  TT_RELEASE_SAFELY(_response);
  TT_RELEASE_SAFELY(_responseData);
  TT_RELEASE_SAFELY(_urlPath);
  TT_RELEASE_SAFELY(_cacheKey);
  TT_RELEASE_SAFELY(_requests);
  [super dealloc];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Private


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connectToURL:(NSURL*)URL {
  TTDPRINT(@"Connecting to %@", _urlPath);
  TTNetworkRequestStarted();

  TTURLRequest* request = _requests.count == 1 ? [_requests objectAtIndex:0] : nil;
  NSURLRequest* URLRequest = [_queue createNSURLRequest:request URL:URL];

  _connection = [[NSURLConnection alloc] initWithRequest:URLRequest delegate:self];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dispatchLoadedBytes:(NSInteger)bytesLoaded expected:(NSInteger)bytesExpected
{
  for (TTURLRequest* request in [[_requests copy] autorelease]) 
  {
    request.totalBytesLoaded = bytesLoaded;
    request.totalBytesExpected = bytesExpected;

    for (id<TTURLRequestDelegate> delegate in request.delegates) 
    {
      if (delegate && [delegate respondsToSelector:@selector(requestDidUploadData:)]) 
      {
        [delegate requestDidUploadData:request];
      }
    }
  }
}

- (void)dispatchDownloadedPercent:(CGFloat)percent totalLength:(long long)total
{
    for (TTURLRequest* request in [[_requests copy] autorelease]) 
    {
        for (id<TTURLRequestDelegate> delegate in request.delegates) 
        {
            if (delegate && [delegate respondsToSelector:@selector(request:didDownloadPercent:totalLenght:)]) 
            {
                [delegate request:request didDownloadPercent:percent totalLenght:total];
            }
        }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Public


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)addRequest:(TTURLRequest*)request {
  // TODO (jverkoey April 27, 2010): Look into the repercussions of adding a request with
  // different properties.
  //TTDASSERT([_urlPath isEqualToString:request.urlPath]);
  //TTDASSERT(_cacheKey == request.cacheKey);
  //TTDASSERT(_cachePolicy == request.cachePolicy);
  //TTDASSERT(_cacheExpirationAge == request.cacheExpirationAge);

  [_requests addObject:request];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)removeRequest:(TTURLRequest*)request {
  [_requests removeObject:request];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)load:(NSURL*)URL {
  if (!_connection) {
    [self connectToURL:URL];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)loadSynchronously:(NSURL*)URL {
  // This method simulates an asynchronous network connection. If your delegate isn't being called
  // correctly, this would be the place to start tracing for errors.
  TTNetworkRequestStarted();

  TTURLRequest* request = _requests.count == 1 ? [_requests objectAtIndex:0] : nil;
  NSURLRequest* URLRequest = [_queue createNSURLRequest:request URL:URL];

  NSHTTPURLResponse* response = nil;
  NSError* error = nil;
  NSData* data = [NSURLConnection
                  sendSynchronousRequest: URLRequest
                  returningResponse: &response
                  error: &error];

  if (nil != error) {
    TTNetworkRequestStopped();

    TT_RELEASE_SAFELY(_responseData);
    TT_RELEASE_SAFELY(_connection);

    [_queue loader:self didFailLoadWithError:error];
  } else {
    [self connection:nil didReceiveResponse:(NSHTTPURLResponse*)response];
    [self connection:nil didReceiveData:data];

    [self connectionDidFinishLoading:nil];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)cancel:(TTURLRequest*)request {
  NSUInteger requestIndex = [_requests indexOfObject:request];
  if (requestIndex != NSNotFound) {
    request.isLoading = NO;

    for (id<TTURLRequestDelegate> delegate in request.delegates) {
      if (delegate && [delegate respondsToSelector:@selector(requestDidCancelLoad:)]) {
        [delegate requestDidCancelLoad:request];
      }
    }

    [_requests removeObjectAtIndex:requestIndex];
  }
    
    // 保存断点续传断点文件
    //
    if (request.breakSeqment)
    {
        [request.requestCache storeSegment:_totalLength
                                       current:_responseData.length + _totalCurrentLen
                                          data:_responseData
                                           key:request.cacheKey];
    }

  if (![_requests count]) {
    [_queue loaderDidCancel:self wasLoading:!!_connection];
    if (nil != _connection) {
      TTNetworkRequestStopped();
      [_connection cancel];
      TT_RELEASE_SAFELY(_connection);
    }
    return NO;

  } 
    
    return YES;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (NSError*)processResponse:(NSHTTPURLResponse*)response data:(id)data {
  for (TTURLRequest* request in _requests) {
    NSError* error = [request.response request:request processResponse:response data:data];
    if (error) {
      return error;
    }
  }
  return nil;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dispatchError:(NSError*)error {
  for (TTURLRequest* request in [[_requests copy] autorelease]) {
    request.isLoading = NO;

    for (id<TTURLRequestDelegate> delegate in request.delegates) {
      if (delegate && [delegate respondsToSelector:@selector(request:didFailLoadWithError:)]) {
        [delegate request:request didFailLoadWithError:error];
      }
    }
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dispatchLoaded:(NSDate*)timestamp {
  for (TTURLRequest* request in [[_requests copy] autorelease]) {
    request.timestamp = timestamp;
    request.isLoading = NO;
      
      // 处理下载完成的数据
      //
      if (request.breakSeqment)
      {
          [request.requestCache finishSegment:_responseData key:request.cacheKey];
          request.breakSeqment = NO;
          
          _totalCurrentLen = 0;
          _totalLength = 0;
      }
      
    for (id<TTURLRequestDelegate> delegate in request.delegates) {
      if (delegate && [delegate respondsToSelector:@selector(requestDidFinishLoad:)]) {
        [delegate requestDidFinishLoad:request];
      }
    }
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dispatchAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge {
  for (TTURLRequest* request in [[_requests copy] autorelease]) {

    for (id<TTURLRequestDelegate> delegate in request.delegates) {
      if (delegate && [delegate respondsToSelector:@selector(request:didReceiveAuthenticationChallenge:)]) {
        [delegate request:request didReceiveAuthenticationChallenge:challenge];
      }
    }
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)cancel {
  NSArray* requestsToCancel = [_requests copy];
  for (id request in requestsToCancel) {
    [self cancel:request];
  }
  [requestsToCancel release];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSURLConnectionDelegate


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSHTTPURLResponse*)response {
  _response = [response retain];
      
    NSDictionary* headers = [response allHeaderFields];
    NSInteger contentLength = [[headers objectForKey:@"Content-Length"] floatValue];
    
    // 断点续传接受剩下的字节
    //
    if (_response.statusCode != 206)
    {
        _totalLength = llabs([response expectedContentLength]);
    }
    
  // If you hit this assertion it's because a massive file is about to be downloaded.
  // If you're sure you want to do this, add the following line to your app delegate startup
  // method. Setting the max content length to zero allows anything to go through. If you just
  // want to raise the limit, set it to any positive byte size.
  // [[TTURLRequestQueue mainQueue] setMaxContentLength:0]
  TTDASSERT(0 == _queue.maxContentLength || contentLength <=_queue.maxContentLength);

  if (contentLength > _queue.maxContentLength && _queue.maxContentLength) 
  {
    TTDPRINT(@"MAX CONTENT LENGTH EXCEEDED (%d) %@",
                    contentLength, _urlPath);
    
      for (TTURLRequest* request in [[_requests copy] autorelease]) {
          request.isLoading = NO;
          
          for (id<TTURLRequestDelegate> delegate in request.delegates) {
              if (delegate && [delegate respondsToSelector:@selector(requestDidCancelMaxLoad:)]) {
                  [delegate requestDidCancelMaxLoad:request];
              }
          }
      }
      
      [self cancel];
  }

  _responseData = [[NSMutableData alloc] initWithCapacity:contentLength];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data 
{
    [_responseData appendData:data];
    CGFloat nowLength = [[NSNumber numberWithInteger:_responseData.length] floatValue] + _totalCurrentLen;
    
    CGFloat total = [[NSNumber numberWithLongLong:_totalLength] floatValue];
    
    if (total > nowLength)
    {
        CGFloat percent = nowLength / total;
        [self dispatchDownloadedPercent:percent totalLength:total];
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (NSCachedURLResponse *)connection: (NSURLConnection *)connection
                  willCacheResponse: (NSCachedURLResponse *)cachedResponse {
  return nil;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)           connection: (NSURLConnection *)connection
              didSendBodyData: (NSInteger)bytesWritten
            totalBytesWritten: (NSInteger)totalBytesWritten
    totalBytesExpectedToWrite: (NSInteger)totalBytesExpectedToWrite {
  [self dispatchLoadedBytes:totalBytesWritten expected:totalBytesExpectedToWrite];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  TTNetworkRequestStopped();

    //TTDPRINT(@"Response status code: %d", _response.statusCode);

    [self dispatchDownloadedPercent:1.0 totalLength:_totalLength];
    
  // We need to accept valid HTTP status codes, not only 200.
  if (_response.statusCode == 599 || (_response.statusCode >= 200 && _response.statusCode < 300))   //  针对野火视频客户端 statusCode 为599时也应处理。其他程序应区别对待。edited by 滕松 on 20130305
  {
      [_queue loader:self didLoadResponse:_response data:_responseData];
  }
  else if (_response.statusCode == 304) {
    [_queue loader:self didLoadUnmodifiedResponse:_response];

  } else {
    TTDPRINT(@"  FAILED LOADING (%d) %@",
                    _response.statusCode, _urlPath);
    NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:_response.statusCode
                                     userInfo:nil];
    [_queue loader:self didFailLoadWithError:error];
  }


    
  TT_RELEASE_SAFELY(_responseData);
  TT_RELEASE_SAFELY(_connection);
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge{
  TTDPRINT(@"  RECEIVED AUTH CHALLENGE LOADING %@ ", _urlPath);
  [_queue loader:self didReceiveAuthenticationChallenge:challenge];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  TTDPRINT(@"  FAILED LOADING %@ FOR %@", _urlPath, error);

  TTNetworkRequestStopped();

  TT_RELEASE_SAFELY(_responseData);
  TT_RELEASE_SAFELY(_connection);

  if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCannotFindHost
      && _retriesLeft) {
    // If there is a network error then we will wait and retry a few times in case
    // it was just a temporary blip in connectivity.
    --_retriesLeft;
    [self load:[NSURL URLWithString:_urlPath]];

  } else {
    [_queue loader:self didFailLoadWithError:error];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Accessors


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)isLoading {
  return !!_connection;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
// Deprecated
- (NSString*)URL {
  return _urlPath;
}


@end
