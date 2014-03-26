//
//  main.m
//  SEGBlock
//
//  Created by Samuel E. Giddins on 3/26/14.
//  Copyright (c) 2014 Samuel E. Giddins. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SEGBlock/SEGBlock.h>

int main(int argc, const char *argv[])
{

    @autoreleasepool
    {

        // insert code here...
        NSLog(@"Hello, World!");
        NSString *string = [NSString stringWithFormat:@"%@", @"string"];
        __block NSString *blockString = [NSString stringWithFormat:@"Block %@", string];
        NSNumber *number = @(M_PI);
        __weak NSNumber *weakNumber = number;
        SEGBlock *block = [SEGBlock blockWithBlock:^{
            NSLog(@"Invoked!");
            NSLog(@"String: %@", string);
            NSLog(@"Block String: %@", blockString);
            NSLog(@"Weak Number: %@", weakNumber);
            return weakNumber.floatValue;
        }];
        NSLog(@"Block : %@", block);
        [block invoke];

        SEGBlock *crazyBlock = [SEGBlock blockWithBlock:^(NSString *string1, NSString *string2) {
            NSLog(@"Strings: %@", @[string1 ?: @"", string2 ?: @""]);
            return ^{};
        }];
        NSLog(@"CrazyBlock : %@", crazyBlock);
    }
    return 0;
}
