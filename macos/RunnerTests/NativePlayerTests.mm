#import <XCTest/XCTest.h>

#include <string>
#include <variant>

#include "FoundationValueConversion.h"
#include "VideoGeometry.h"
#import "LineupNativePlayer.h"

using lineup::player::Value;
using lineup::player::ValueList;
using lineup::player::ValueMap;

@interface FoundationValueConversionTests : XCTestCase
@end

@implementation FoundationValueConversionTests

// The standard codec decodes Dart bool, int, and double into NSNumbers that
// differ only in their CoreFoundation type. The protocol's typed lookups
// (stopId, loadId, revision versus seconds and volume) depend on keeping
// them distinct.
- (void)testNumbersKeepBoolIntegerAndDoubleDistinct {
  const Value yes = lineup::ToValue(@YES);
  const Value no = lineup::ToValue(@NO);
  XCTAssertTrue(std::holds_alternative<bool>(yes));
  XCTAssertTrue(std::get<bool>(yes));
  XCTAssertTrue(std::holds_alternative<bool>(no));
  XCTAssertFalse(std::get<bool>(no));

  // 0 and 1 integers must not be mistaken for booleans.
  for (NSNumber* number in @[ @0, @1, @(int64_t{1} << 40), @(-7) ]) {
    const Value value = lineup::ToValue(number);
    XCTAssertTrue(std::holds_alternative<int64_t>(value), @"%@", number);
    XCTAssertEqual(std::get<int64_t>(value), number.longLongValue);
  }

  // A whole-valued double stays a double, so an integer-only field rejects it.
  const Value whole = lineup::ToValue(@1.0);
  XCTAssertTrue(std::holds_alternative<double>(whole));
  XCTAssertEqual(std::get<double>(whole), 1.0);
  const Value fraction = lineup::ToValue(@2.5);
  XCTAssertEqual(std::get<double>(fraction), 2.5);
  XCTAssertFalse(lineup::player::AsInt(&whole).has_value());
}

- (void)testNullStringAndUnsupportedObjects {
  XCTAssertTrue(std::holds_alternative<std::monostate>(lineup::ToValue(nil)));
  XCTAssertTrue(std::holds_alternative<std::monostate>(
      lineup::ToValue([NSNull null])));

  const Value text = lineup::ToValue(@"café ☃");
  XCTAssertTrue(std::get<std::string>(text) == "caf\xc3\xa9 \xe2\x98\x83");
  XCTAssertTrue(std::get<std::string>(lineup::ToValue(@"")).empty());

  // Embedded NUL bytes are kept, so validation sees the whole string.
  NSString* withNul = [[NSString alloc] initWithBytes:"a\0b"
                                               length:3
                                             encoding:NSUTF8StringEncoding];
  XCTAssertEqual(std::get<std::string>(lineup::ToValue(withNul)).size(), 3u);

  // An unpaired surrogate has no UTF-8 form; it must not become a string.
  const unichar lone = 0xD800;
  NSString* invalid = [NSString stringWithCharacters:&lone length:1];
  const Value invalidValue = lineup::ToValue(invalid);
  XCTAssertFalse(std::holds_alternative<std::string>(invalidValue));
  XCTAssertFalse(std::holds_alternative<std::monostate>(invalidValue));

  // Objects outside the protocol become a non-null placeholder that fails
  // every typed lookup.
  const Value data = lineup::ToValue([NSData dataWithBytes:"x" length:1]);
  XCTAssertTrue(std::holds_alternative<ValueList>(data));
  XCTAssertTrue(std::get<ValueList>(data).empty());
}

- (void)testNestedCollectionsAndNonStringKeys {
  NSDictionary* arguments = @{
    @"type" : @"audio",
    @"id" : [NSNull null],
    @"nested" : @{@"list" : @[ @1, @2.5, @YES, @"x", [NSNull null] ]},
    @7 : @"numeric key",
    @[ @1 ] : @"list key",
  };
  const auto map = lineup::ToValueMap(arguments);
  XCTAssertTrue(map.has_value());
  XCTAssertEqual(map->size(), 3u);
  XCTAssertTrue(*lineup::player::FindString(&*map, "type") == "audio");
  XCTAssertTrue(std::holds_alternative<std::monostate>(map->at("id")));

  const ValueMap* nested = lineup::player::AsMap(&map->at("nested"));
  XCTAssertTrue(nested != nullptr);
  const auto& list = std::get<ValueList>(nested->at("list"));
  XCTAssertEqual(list.size(), 5u);
  XCTAssertTrue(std::holds_alternative<int64_t>(list[0]));
  XCTAssertTrue(std::holds_alternative<double>(list[1]));
  XCTAssertTrue(std::holds_alternative<bool>(list[2]));
  XCTAssertTrue(std::holds_alternative<std::string>(list[3]));
  XCTAssertTrue(std::holds_alternative<std::monostate>(list[4]));

  XCTAssertFalse(lineup::ToValueMap(@[ @1 ]).has_value());
  XCTAssertFalse(lineup::ToValueMap(nil).has_value());
}

// Events go back through the standard codec, which distinguishes bool from
// numbers by CFBoolean identity, and Dart's report parser requires every key
// to be present even when its value is null.
- (void)testEventsEncodeTypedFoundationValuesAndKeepNullKeys {
  const ValueMap event{
      {"type", Value("display")},
      {"revision", Value(int64_t{3})},
      {"wrote", Value(false)},
      {"peak", Value(10.5)},
      {"activeColorMode", Value()},
      {"tracks", Value(ValueList{Value(ValueMap{{"id", Value(1)}})})},
  };
  NSDictionary* encoded = lineup::ToFoundationMap(event);
  XCTAssertEqual(encoded.count, 6u);
  XCTAssertEqualObjects(encoded[@"type"], @"display");
  XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)encoded[@"wrote"]),
                 CFBooleanGetTypeID());
  XCTAssertEqual(encoded[@"wrote"], (__bridge id)kCFBooleanFalse);
  XCTAssertNotEqual(CFGetTypeID((__bridge CFTypeRef)encoded[@"revision"]),
                    CFBooleanGetTypeID());
  XCTAssertFalse(CFNumberIsFloatType((__bridge CFNumberRef)encoded[@"revision"]));
  XCTAssertEqual([encoded[@"revision"] longLongValue], 3);
  XCTAssertTrue(CFNumberIsFloatType((__bridge CFNumberRef)encoded[@"peak"]));
  XCTAssertEqual(encoded[@"activeColorMode"], [NSNull null]);
  XCTAssertEqualObjects(encoded[@"tracks"], (@[ @{@"id" : @1} ]));

  // A round trip preserves the value kinds.
  const auto decoded = lineup::ToValueMap(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertTrue(*decoded == event);
}

@end

@interface VideoGeometryTests : XCTestCase
@end

@implementation VideoGeometryTests

// Parsing and bounds are the core's (player_core_contract_test); these cover
// only the macOS presentation rules.
- (void)testFrameIsInPointsWithATopLeftOrigin {
  // The backing scale is applied to the layer, not to the frame.
  const CGRect frame = lineup::VideoFrame(lineup::VideoRect{10.5, 20, 640, 360.25, 2});
  XCTAssertEqual(frame.origin.x, 10.5);
  XCTAssertEqual(frame.origin.y, 20);
  XCTAssertEqual(frame.size.width, 640);
  XCTAssertEqual(frame.size.height, 360.25);
}

- (void)testVisibilityRequiresAreaAndAVisibleWindow {
  const lineup::VideoRect area{0, 0, 320, 180, 2};
  XCTAssertTrue(lineup::VideoVisible(area, false, false));
  XCTAssertFalse(lineup::VideoVisible(std::nullopt, false, false));
  XCTAssertFalse(lineup::VideoVisible(lineup::VideoRect{0, 0, 0, 180, 2}, false, false));
  XCTAssertFalse(lineup::VideoVisible(lineup::VideoRect{0, 0, 320, 0, 2}, false, false));
  XCTAssertFalse(lineup::VideoVisible(area, true, false));
  XCTAssertFalse(lineup::VideoVisible(area, false, true));
}

// Hiding must never empty the frame: the swapchain extent comes from the
// layer bounds, and a zero extent fails mpv's video output for a load that
// starts while video is hidden.
- (void)testHiddenVideoKeepsANonEmptyFrame {
  const CGRect previous = CGRectMake(40, 60, 640, 360);
  XCTAssertTrue(CGRectEqualToRect(
      lineup::RetainedVideoFrame(lineup::VideoRect{1, 2, 3, 4, 1}, previous),
      CGRectMake(1, 2, 3, 4)));
  XCTAssertTrue(CGRectEqualToRect(
      lineup::RetainedVideoFrame(lineup::VideoRect{5, 5, 0, 0, 1}, previous),
      previous));
  XCTAssertTrue(CGRectEqualToRect(
      lineup::RetainedVideoFrame(std::nullopt, previous), previous));
  XCTAssertTrue(CGRectEqualToRect(
      lineup::RetainedVideoFrame(std::nullopt, CGRectMake(0, 0, 0, 0)),
      CGRectMake(0, 0, 1, 1)));
}

- (void)testDrawableSizeIsBoundsTimesBackingScale {
  CGSize size = lineup::DrawableSize(CGSizeMake(640, 360), 2);
  XCTAssertEqual(size.width, 1280);
  XCTAssertEqual(size.height, 720);
  size = lineup::DrawableSize(CGSizeMake(100.3, 50.7), 1);
  XCTAssertEqual(size.width, 100);
  XCTAssertEqual(size.height, 51);
  // Never empty, never beyond the Metal texture limit, and a bad scale is
  // treated as 1.
  size = lineup::DrawableSize(CGSizeMake(0, 0), 2);
  XCTAssertEqual(size.width, 1);
  XCTAssertEqual(size.height, 1);
  size = lineup::DrawableSize(CGSizeMake(1e9, 10), 2);
  XCTAssertEqual(size.width, lineup::kMaxDrawableDimension);
  size = lineup::DrawableSize(CGSizeMake(10, 10), 0);
  XCTAssertEqual(size.width, 10);
}

@end

// Exercise the adapter's production request method without initializing media
// or launching a Flutter engine. The window boundary controls AppKit's observed
// style and notifications so both sides of a transition are deterministic.
@interface LineupNativePlayer (FullscreenTests)
- (void)setFullscreen:(bool)fullscreen result:(FlutterResult)result;
@end

@interface FullscreenTestWindow : NSObject
@property(nonatomic) NSWindowStyleMask styleMask;
@property(nonatomic) NSUInteger toggleCount;
- (void)toggleFullScreen:(id)sender;
@end

@implementation FullscreenTestWindow
- (void)toggleFullScreen:(id)sender {
  self.toggleCount += 1;
}
@end

@interface FullscreenTestMessenger : NSObject <FlutterBinaryMessenger>
@end

@implementation FullscreenTestMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {}
- (void)sendOnChannel:(NSString*)channel
             message:(NSData*)message
         binaryReply:(FlutterBinaryReply)callback {}
- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
  return 1;
}
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {}
@end

@interface FullscreenRequestTests : XCTestCase
@end

@implementation FullscreenRequestTests

- (void)checkMatchingRequestsDuringTransition:(BOOL)started {
  XCTAssertTrue(NSThread.isMainThread);
  for (NSNumber* initialState in @[ @NO, @YES ]) {
    const bool current = initialState.boolValue;
    FullscreenTestWindow* window = [FullscreenTestWindow new];
    window.styleMask = current ? NSWindowStyleMaskFullScreen : 0;
    FullscreenTestMessenger* messenger = [FullscreenTestMessenger new];
    NSView* videoHost = [[NSView alloc] initWithFrame:NSZeroRect];
    LineupNativePlayer* player = [[LineupNativePlayer alloc]
        initWithMessenger:messenger
                videoHost:videoHost
                   window:(NSWindow*)window];

    // A real nonmatching request creates the pending toggle and must remain
    // outstanding while subsequent requests for the current state succeed.
    __block NSUInteger outstandingReplies = 0;
    [player setFullscreen:!current result:^(id result) {
      XCTAssertNil(result);
      outstandingReplies += 1;
    }];
    XCTAssertEqual(window.toggleCount, 1u);
    XCTAssertEqual(outstandingReplies, 0u);
    if (started) {
      [NSNotificationCenter.defaultCenter
          postNotificationName:current ? NSWindowWillExitFullScreenNotification
                                       : NSWindowWillEnterFullScreenNotification
                        object:window];
    }
    NSNumber* requestId = [player valueForKey:@"nextFullscreenRequest"];
    __block NSUInteger matchingReplies = 0;
    [player setFullscreen:current result:^(id result) {
      XCTAssertNil(result);
      matchingReplies += 1;
    }];
    // Assert before any notification/run-loop work: this reply is synchronous.
    XCTAssertEqual(matchingReplies, 1u);
    XCTAssertEqualObjects([player valueForKey:@"nextFullscreenRequest"],
                          requestId);
    XCTAssertEqual(window.toggleCount, 1u);
    XCTAssertEqual(outstandingReplies, 0u);

    // Completing the original transition must settle only that request,
    // without a queued matching request reversing it or replying again.
    window.styleMask = current ? 0 : NSWindowStyleMaskFullScreen;
    [NSNotificationCenter.defaultCenter
        postNotificationName:current ? NSWindowDidExitFullScreenNotification
                                     : NSWindowDidEnterFullScreenNotification
                      object:window];
    XCTAssertEqual(outstandingReplies, 1u);
    XCTAssertEqual(matchingReplies, 1u);
    XCTAssertEqual(window.toggleCount, 1u);
    [player shutdown];
    XCTAssertEqual(outstandingReplies, 1u);
    XCTAssertEqual(matchingReplies, 1u);
  }
}

- (void)testMatchingRequestsCompleteWhileToggleIsPending {
  [self checkMatchingRequestsDuringTransition:NO];
}

- (void)testMatchingRequestsCompleteWhileTransitionIsActive {
  [self checkMatchingRequestsDuringTransition:YES];
}

@end
