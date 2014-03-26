// SEGBlock.m
//
// Copyright (c) 2014 Samuel E. Giddins
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "SEGBlock.h"
#import "BRYDescriptionBuilder.h"

typedef NS_OPTIONS(int32_t, SEGBlockFlags) {
    SEGBlockFlagsHasCopyDisposeHelpers = (1 << 25),
    SEGBlockFlagsHasSignature = (1 << 30),
    SEGBlockFlagsHasExtendedLayout = (1 << 31),
};

// Extended layout encoding.

// Values for Block_descriptor_3->layout with BLOCK_HAS_EXTENDED_LAYOUT
// and for Block_byref_3->layout with BLOCK_BYREF_LAYOUT_EXTENDED

// If the layout field is less than 0x1000, then it is a compact encoding
// of the form 0xXYZ: X strong pointers, then Y byref pointers,
// then Z weak pointers.

// If the layout field is 0x1000 or greater, it points to a
// string of layout bytes. Each byte is of the form 0xPN.
// Operator P is from the list below. Value N is a parameter for the operator.
// Byte 0x00 terminates the layout; remaining block data is non-pointer bytes.

typedef NS_ENUM(int32_t, SEGBlockExtendedLayoutFlags) {
    SEG_BLOCK_LAYOUT_ESCAPE = 0, // N=0 halt, rest is non-pointer. N!=0 reserved.
    SEG_BLOCK_LAYOUT_NON_OBJECT_BYTES = 1, // N bytes non-objects
    SEG_BLOCK_LAYOUT_NON_OBJECT_WORDS = 2, // N words non-objects
    SEG_BLOCK_LAYOUT_STRONG = 3, // N words strong pointers
    SEG_BLOCK_LAYOUT_BYREF = 4, // N words byref pointers
    SEG_BLOCK_LAYOUT_WEAK = 5, // N words weak pointers
    SEG_BLOCK_LAYOUT_UNRETAINED = 6, // N words unretained pointers
    SEG_BLOCK_LAYOUT_UNKNOWN_WORDS_7 = 7, // N words, reserved
    SEG_BLOCK_LAYOUT_UNKNOWN_WORDS_8 = 8, // N words, reserved
    SEG_BLOCK_LAYOUT_UNKNOWN_WORDS_9 = 9, // N words, reserved
    SEG_BLOCK_LAYOUT_UNKNOWN_WORDS_A = 0xA, // N words, reserved
    SEG_BLOCK_LAYOUT_UNUSED_B = 0xB, // unspecified, reserved
    SEG_BLOCK_LAYOUT_UNUSED_C = 0xC, // unspecified, reserved
    SEG_BLOCK_LAYOUT_UNUSED_D = 0xD, // unspecified, reserved
    SEG_BLOCK_LAYOUT_UNUSED_E = 0xE, // unspecified, reserved
    SEG_BLOCK_LAYOUT_UNUSED_F = 0xF, // unspecified, reserved
};

typedef struct _SEGBlock {
    Class isa;
    volatile SEGBlockFlags flags;
    __unused int32_t reserved;
    void (*invoke)(struct _SEGBlock *block, ...);
    struct {
        unsigned long int reserved;
        unsigned long int size;
        // requires BKBlockFlagsHasCopyDisposeHelpers
        void (*copy)(void *dst, const void *src);
        void (*dispose)(const void *);
        // requires BKBlockFlagsHasSignature
        const char *signature;
        const char *layout;
    } *descriptor;
    // imported variables
} *SEGBlockRef;

@interface SEGBlock ()

@property (nonatomic, copy) id block;
@property (readonly) SEGBlockRef blockStruct;

@end

@implementation SEGBlock

+ (instancetype)blockWithBlock:(id)block
{
    return [[self alloc] initWithBlock:block];
}

- (instancetype)initWithBlock:(id)block
{
    self = [super init];
    if (!self) return nil;
    self.block = block;
    return self;
}

- (SEGBlockRef)blockStruct
{
    return (__bridge SEGBlockRef)self.block;
}

- (void)invoke
{
    NSAssert(self.typeSignature.numberOfArguments == 1, nil);
    self.blockStruct->invoke(self.blockStruct);
}

- (NSDictionary *)capturedVariables
{
    uintptr_t vars = (self.blockStruct->descriptor->size - sizeof(*self.blockStruct)) / sizeof(void *);
    void **vars_array = (void *)self.blockStruct + sizeof(struct _SEGBlock);
    NSMutableDictionary *capturedVariables = [NSMutableDictionary dictionaryWithCapacity:vars];
    if (self.blockStruct->flags & SEGBlockFlagsHasExtendedLayout) {
        //        NSLog(@"Has extended layout");
        uintptr_t layout = (uintptr_t)self.blockStruct->descriptor->layout;
        if (layout < 0x1000) {
            //            NSLog(@"Compact layout encoding: 0x%lx", layout);
            uintptr_t strongCount = (layout & 0xF00) >> 8, byrefCount = (layout & 0xF0) >> 4, weakCount = layout & 0xF;
            for (uintptr_t i = 0; i < strongCount; i++) {
                id var = (__bridge id)vars_array[i];
                capturedVariables[@"strong"] = capturedVariables[@"strong"] ?: [NSMutableArray arrayWithCapacity:strongCount];
                [capturedVariables[@"strong"] addObject:var];
            }
            for (uintptr_t i = strongCount; i < strongCount + byrefCount; i++) {
                //                void *var = vars_array[i];
                capturedVariables[@"byref"] = @(byrefCount);
            }
            for (uintptr_t i = strongCount + byrefCount; i < strongCount + byrefCount + weakCount; i++) {
                id var = (__bridge id)vars_array[i];
                capturedVariables[@"weak"] = capturedVariables[@"weak"] ?: [NSMutableArray arrayWithCapacity:strongCount];
                [capturedVariables[@"weak"] addObject:var];
            }
        } else {
            NSLog(@"Layout bytes: %s", self.blockStruct->descriptor->layout);
            uintptr_t layoutCount = strlen(self.blockStruct->descriptor->layout);
            for (uintptr_t i = 0; i < layoutCount; i++) {
                uintptr_t layout = self.blockStruct->descriptor->layout[i];
                NSLog(@"0x%lx", layout);
            }
        }
    }
    return capturedVariables;
}

// Courtesy of https://github.com/zwaldowski/BlocksKit/commit/6eac98be90526a8508b1298dfaead8a69502eabd#diff-0460b8bdc2edadedfa24ad519ae1a988R96

/** Inspects the given block literal and returns a compatible type signature.
 
 Unlike a typical method signature, a block type signature has no `self` (`'@'`)
 or `_cmd` (`':'`) parameter, but instead just one parameter for the block itself
 (`'@?'`).
 
 @param block An Objective-C block literal
 @return A method signature matching the declared prototype for the block
 */
- (NSMethodSignature *)typeSignature
{
    SEGBlockRef layout = self.blockStruct;

    if (!(layout->flags & SEGBlockFlagsHasSignature))
        return nil;

    void *desc = layout->descriptor;
    desc += 2 * sizeof(unsigned long int);

    if (layout->flags & SEGBlockFlagsHasCopyDisposeHelpers)
        desc += 2 * sizeof(void *);

    if (!desc)
        return nil;

    const char *signature = (*(const char **)desc);

    return [NSMethodSignature signatureWithObjCTypes:signature];
}

- (NSArray *)argumentTypes
{
    NSMethodSignature *methodSignature = self.typeSignature;
    NSUInteger argCount = methodSignature.numberOfArguments;
    NSMutableArray *args = [NSMutableArray arrayWithCapacity:argCount];
    for (NSUInteger i = 1; i < argCount; i++) {
        const char *type = [methodSignature getArgumentTypeAtIndex:i];
        [args addObject:[NSString stringWithUTF8String:type]];
    }
    return args;
}

- (NSString *)returnType
{
    return @(self.typeSignature.methodReturnType);
}

- (NSString *)description
{
    return [[[[BRYDescriptionBuilder
        builderWithObject:self] appendObject:[super description]
                                    withName:@"super"] appendPropertiesWithKeyPaths:@[
#ifdef DEBUG
                                                                                       @"block",
#endif
                                                                                       @"capturedVariables",
                                                                                       @"typeSignature",
                                                                                       @"argumentTypes",
                                                                                       @"returnType"
                                                                                    ]] description];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end
