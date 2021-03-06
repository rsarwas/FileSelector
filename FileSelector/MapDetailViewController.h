//
//  MapDetailViewController.h
//  FileSelector
//
//  Created by Regan Sarwas on 12/5/13.
//  Copyright (c) 2013 GIS Team. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Map.h"

@interface MapDetailViewController : UIViewController <CLLocationManagerDelegate>

@property (nonatomic, strong) Map *map;

@end
