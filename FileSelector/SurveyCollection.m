//
//  SurveyCollection.m
//  FileSelector
//
//  Created by Regan Sarwas on 12/3/13.
//  Copyright (c) 2013 GIS Team. All rights reserved.
//

#import "SurveyCollection.h"
#import "NSArray+map.h"

@interface SurveyCollection()
//FIXME:  The following should be private properties.
//They are public temporarily as a convenience for the subclass
//@property (strong,nonatomic) NSMutableArray *items;
//@property (strong, nonatomic) FSSurvey* selectedSurvey;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic) BOOL isLoaded;
//selectedIndex < 0  meaning that no item is selected
@property (nonatomic) NSInteger selectedIndex;
@end

@implementation SurveyCollection

static SurveyCollection *_sharedCollection;

+ (SurveyCollection *) sharedCollection {
    return _sharedCollection;
}

#pragma mark - private properties

- (NSMutableArray *)items
{
    if (!_items) {
        _items = [NSMutableArray new];
    }
    return _items;
}

- (void) setSelectedIndex:(NSInteger)selectedIndex
{
    if (_selectedIndex == selectedIndex)
        return;
    //Since self.items.count is unsigned, the comparison is unsigned, so 2 < -1
    if (0 < selectedIndex && self.items.count <= selectedIndex) {
        return; //ignore bogus indexes
    }
    //Allow setting selected index to -1 (or any negative) to indicate no selected item
    _selectedIndex = selectedIndex;
    //FIXME:  use settings
    //[Settings manager].currentSurveyIndex = selectedIndex;
    [[NSUserDefaults standardUserDefaults] setInteger:selectedIndex forKey:@"currentSurveyIndex"];
}


#pragma mark - TableView Data Source Support

- (Survey *)surveyAtIndex:(NSUInteger)index
{
    if (self.items.count <= index) return nil; //safety check
    return self.items[index];
}

-(NSUInteger)numberOfSurveys
{
    return self.items.count;
}

-(void)removeSurveyAtIndex:(NSUInteger)index
{
    if (self.items.count <= index) return; //safety check
    Survey *item = [self surveyAtIndex:index];
    [[NSFileManager defaultManager] removeItemAtURL:item.url error:nil];
    [self.items removeObjectAtIndex:index];
    [self saveCache];
    if (index == self.selectedIndex) {
        self.selectedIndex = -1;
    }
    if (index < self.selectedIndex) {
        self.selectedIndex = self.selectedIndex - 1;
    }
}

-(void)moveSurveyAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex
{
    if (self.items.count <= fromIndex || self.items.count <= toIndex) return;  //safety check
    if (fromIndex == toIndex)
        return;

    //adjust the selected Index
    if (self.selectedIndex == fromIndex) {
        self.selectedIndex = toIndex;
    } else {
        if (fromIndex < self.selectedIndex && self.selectedIndex <= toIndex) {
            self.selectedIndex = self.selectedIndex - 1;
        } else {
            if (toIndex <= self.selectedIndex && self.selectedIndex < fromIndex) {
                self.selectedIndex = self.selectedIndex + 1;
            }
        }
    }
    
    //move the item
    id temp = self.items[fromIndex];
    [self.items removeObjectAtIndex:fromIndex];
    [self.items insertObject:temp atIndex:toIndex];
    [self saveCache];
}

- (void)setSelectedSurvey:(NSUInteger)index
{
    if (index < self.items.count) {
        self.selectedIndex = index;
    }
}

- (Survey *)selectedSurvey
{
    if (self.selectedIndex < 0 || self.items.count <= self.selectedIndex) {
        return nil;
    }
    if (self.items.count == 0) {
        return nil;
    }
    return self.items[self.selectedIndex];
}


- (NSInteger)newSurveyWithProtocol:(SProtocol *)protocol {
    Survey *newSurvey = [[Survey alloc] initWithProtocol:protocol];
    if (newSurvey) {
        NSInteger index = 0;     //insert at top of list
        [self.items insertObject:newSurvey atIndex:index];
        [self saveCache];
        return index;
    } else {
        return -1;
    }
}



- (void)openWithCompletionHandler:(void (^)(BOOL))completionHandler
{
    //TODO: lock access to _sharedCollection
    if (_sharedCollection) {
        if (completionHandler) completionHandler(YES);
    } else {
        dispatch_async(dispatch_queue_create("gov.nps.akr.observer", DISPATCH_QUEUE_CONCURRENT), ^{
            [self readSurveyList];
            _sharedCollection = self;
            BOOL success = self.items != nil;
            //TODO: open each survey item in the background?
            if (completionHandler) {
                completionHandler(success);
            }
        });
    }
}

- (BOOL)openURL:(NSURL *)url
{
    //FIXME: just do it
    return YES;
}

+ (BOOL) collectsURL:(NSURL *)url
{
    return [[url pathExtension] isEqualToString:SURVEY_EXT];
}

- (Survey *)surveyForURL:(NSURL *)url
{
    NSUInteger index = [self.items indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [url isEqual:[obj url]];
    }];
    return (index == NSNotFound) ? nil : [self.items objectAtIndex:index];
}

- (void) readSurveyList
{
    BOOL cacheWasOutdated = NO;
    //FIXME: use settings when integrated with Observer
    //NSArray *cachedSurveyPaths = [Settings manager].surveys;
    //FIXME: remove the following code when integrated with Observer
    NSArray *cachedSurveyUrls = [self cachedSurveyUrls];

    NSMutableSet *files = [NSMutableSet setWithArray:[self surveysInDocuments]];
    // create maps in order from urls saved in defaults  IFF they are found in filesystem
    for (NSURL *url in cachedSurveyUrls) {
        if ([files containsObject:url]) {
            [self.items addObject:[[Survey alloc] initWithURL:url]];
            [files removeObject:url];
        }
    }
    if (self.items.count < cachedSurveyUrls.count) {
        cacheWasOutdated = YES;
    }
    //Add any other Surveys in filesystem (maybe added via iTunes) to end of list from cached list
    for (NSURL *url in files) {
        [self.items addObject:[[Survey alloc] initWithURL:url]];
        cacheWasOutdated = YES;
    }

    //Get the selected index (we can't do this in the accessor, because there isn't a no value Sentinal, i.e 0 is valid)
    //FIXME: Use settings
    //_selectedIndex = [Settings manager].currentSurveyIndex;
    _selectedIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"currentSurveyIndex"];

    if (cacheWasOutdated) {
        [self saveCache];
        //Need to validate/fix the selected index (if files were added or deleted, it may not be valid)
        if (0 <= self.selectedIndex && self.selectedIndex < cachedSurveyUrls.count) {
            NSURL *url = cachedSurveyUrls[self.selectedIndex];
            NSInteger index = [self.items indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                return [url isEqual:((Survey *)obj).url];
            }];
            if (index == NSNotFound) {
                self.selectedIndex = -1;
            } else {
                self.selectedIndex = index;
            }
        } else {
            self.selectedIndex = -1;
        }
    }
}

- (NSArray *) /* of NSURL */ surveysInDocuments
{
    NSMutableArray *localUrls = [[NSMutableArray alloc] init];
    NSURL *documentsDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0];
    NSArray *documents = [[NSFileManager defaultManager]
                          contentsOfDirectoryAtURL:documentsDirectory
                          includingPropertiesForKeys:nil
                          options:NSDirectoryEnumerationSkipsHiddenFiles
                          error:nil];
    if (documents) {
        for (NSURL *url in documents) {
            if ([[url pathExtension] isEqualToString:SURVEY_EXT]) {
                [localUrls addObject:url];
            }
        }
    }
    return localUrls;
}

//FIXME: remove the following code when integrated with Observer
- (NSArray *)cachedSurveyUrls
{
#define DEFAULTS_KEY_SORTED_MAP_LIST @"sorted_map_list"
#define DEFAULTS_DEFAULT_SORTED_MAP_LIST nil
    NSArray *strings = [[NSUserDefaults standardUserDefaults] arrayForKey:DEFAULTS_KEY_SORTED_MAP_LIST];
    //NSDefaults returns a NSArray of NSString, convert to a NSArray of NSURL
    NSArray *urls = [strings mapObjectsUsingBlock:^id(id obj, NSUInteger idx) {
        return [NSURL URLWithString:obj];
    }];
    return urls ?: DEFAULTS_DEFAULT_SORTED_MAP_LIST;
}

- (void)saveCache {
    //[Settings manager].surveys = self.items;
    //FIXME: remove the following code when integrated with Observer
    NSArray *strings = [self.items mapObjectsUsingBlock:^id(id obj, NSUInteger idx) {
        return ((Survey *)obj).url.absoluteString;  //do not use path, it will not convert back to a URL
    }];
    if ([strings isEqual:DEFAULTS_DEFAULT_SORTED_MAP_LIST])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:DEFAULTS_KEY_SORTED_MAP_LIST];
    else
        [[NSUserDefaults standardUserDefaults] setObject:strings forKey:DEFAULTS_KEY_SORTED_MAP_LIST];
    [[NSUserDefaults standardUserDefaults] synchronize];
}




@end
