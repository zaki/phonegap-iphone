/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 * 
 * Copyright (c) 2005-2010, Nitobi Software Inc.
 */

#import <Foundation/Foundation.h>
#import "PGPlugin.h"

@class Reachability;

@interface Network : PGPlugin {
		
}

- (void) isReachable:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options;

@end
