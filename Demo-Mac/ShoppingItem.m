//
//  ShoppingItem.m
//  CouchCocoa
//
//  Created by Jens Alfke on 8/26/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "ShoppingItem.h"
#import <AppKit/NSImage.h>


static NSData* ImageJPEGData(NSImage* image);



@implementation ShoppingItem


@dynamic check, text, created_at;


- (NSDictionary*) propertiesToSave {
    // Initialize created_at the first time the document is saved:
    if (self.created_at == nil)
        self.created_at = [NSDate date];
    return [super propertiesToSave];
}


- (NSImage*) picture {
    if (!_picture) {
        NSData* pictureData = [[self attachmentNamed: @"picture"] content];
        if (pictureData)
            _picture = [[NSImage alloc] initWithData: pictureData];
    }
    return _picture;
}


- (void) setPicture:(NSImage *)picture {
    if (_picture && picture == _picture)
        return;
    
    if (picture)
        [self setAttachmentNamed: @"picture"
                 withContentType: @"image/jpeg"
                         content: ImageJPEGData(picture)];
    else
        [self removeAttachmentNamed: @"picture"];
    _picture = picture;
}


@end


static NSData* ImageJPEGData(NSImage* image) {
    if (!image)
        return nil;
    NSBitmapImageRep* bitmapRep = nil;
    for (NSImageRep* rep in image.representations) {
        if ([rep isKindOfClass: [NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep*) rep;
            break;
        }
    }
    NSCAssert(bitmapRep != nil, @"No bitmap rep");
    return [bitmapRep representationUsingType: NSJPEGFileType properties: nil];
}
