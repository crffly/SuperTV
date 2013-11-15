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

#import "TTStyledFrame.h"
#import "TTStyledNode.h"
#import "SHThree20Global.h"

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TTStyledFrame

@synthesize element = _element, nextFrame = _nextFrame, bounds = _bounds;

///////////////////////////////////////////////////////////////////////////////////////////////////
// NSObject

- (id)initWithElement:(TTStyledElement*)element {
  if (self = [super init]) {
    _element = element;
    _nextFrame = nil;
    _bounds = CGRectZero;
  }
  return self;
}

- (void)dealloc {
  TT_RELEASE_SAFELY(_nextFrame);
  [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// public

- (CGFloat)x {
  return _bounds.origin.x;
}

- (void)setX:(CGFloat)x {
  _bounds.origin.x = x;
}

- (CGFloat)y {
  return _bounds.origin.y;
}

- (void)setY:(CGFloat)y {
  _bounds.origin.y = y;
}

- (CGFloat)width {
  return _bounds.size.width;
}

- (void)setWidth:(CGFloat)width {
  _bounds.size.width = width;
}

- (CGFloat)height {
  return _bounds.size.height;
}

- (void)setHeight:(CGFloat)height {
  _bounds.size.height = height;
}

- (UIFont*)font {
  return nil;
}

- (void)drawInRect:(CGRect)rect {
}

- (TTStyledBoxFrame*)hitTest:(CGPoint)point {
  return [_nextFrame hitTest:point];
}

@end

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TTStyledBoxFrame

@synthesize parentFrame = _parentFrame, firstChildFrame = _firstChildFrame, style = _style;

///////////////////////////////////////////////////////////////////////////////////////////////////
// private

- (void)drawSubframes {
  TTStyledFrame* frame = _firstChildFrame;
  while (frame) {
	  
	  CGRect rect = frame.bounds;
	  //rect.size.width += 50;
    [frame drawInRect:rect];
    frame = frame.nextFrame;
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// NSObject

- (id)init {
  if (self = [super init]) {
    _parentFrame = nil;
    _firstChildFrame = nil;

	  _style = nil;
  }
  return self;
}

- (void)dealloc {
  TT_RELEASE_SAFELY(_firstChildFrame);
	TT_RELEASE_SAFELY(_style);
  [super dealloc];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
// TTStyledFrame

- (UIFont*)font {
  return _firstChildFrame.font;
}

- (void)drawInRect:(CGRect)rect 
{
	if (_style)
	{
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		CGContextSaveGState(ctx);
		
		[_style drawBoxStyle:rect context:ctx];
		
		if (_style.highlighted)
		{
			[[UIColor whiteColor] setFill];
		}
		else {
			[_style.color setFill];
		}

		[self drawSubframes];
		
		CGContextRestoreGState(ctx);
	}
	else {
		[self drawSubframes];
	}
}

- (TTStyledBoxFrame*)hitTest:(CGPoint)point {
  if (CGRectContainsPoint(_bounds, point)) {
    TTStyledBoxFrame* frame = [_firstChildFrame hitTest:point];
    return frame ? frame : self;
  } else if (_nextFrame) {
    return [_nextFrame hitTest:point];
  } else {
    return nil;
  }
}

@end

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TTStyledInlineFrame

@synthesize inlinePreviousFrame = _inlinePreviousFrame, inlineNextFrame = _inlineNextFrame;

- (id)init {
  if (self = [super init]) {
    _inlinePreviousFrame = nil;
    _inlineNextFrame = nil;
  }
  return self;
}

- (void)dealloc {
  [super dealloc];
}

- (TTStyledInlineFrame*)inlineParentFrame {
  if ([_parentFrame isKindOfClass:[TTStyledInlineFrame class]]) {
    return (TTStyledInlineFrame*)_parentFrame;
  } else {
    return nil;
  }  
}

@end

///////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TTStyledTextFrame

@synthesize node = _node, text = _text, font = _font;

///////////////////////////////////////////////////////////////////////////////////////////////////
// NSObject

- (id)initWithText:(NSString*)text element:(TTStyledElement*)element node:(TTStyledTextNode*)node {
  if (self = [super initWithElement:element]) {
    _text = [text copy];
    _node = node;
    _font = nil;
  }
  return self;
}

- (void)dealloc {
  TT_RELEASE_SAFELY(_text);
  TT_RELEASE_SAFELY(_font);
  [super dealloc];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// public

- (void)drawInRect:(CGRect)rect {
	
	[_text drawInRect:rect withFont:_font lineBreakMode:UILineBreakModeWordWrap];
	
}

@end


