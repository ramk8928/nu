/*!
@file nu.m
@description Top-level Nu functions.
@copyright Copyright (c) 2007 Radtastical Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#import <AvailabilityMacros.h>

#import "NuParser.h"
#import "NuSymbol.h"
#import "NuMain.h"
#import "NuExtensions.h"
#import "NuObject.h"
#import "NuObjCRuntime.h"
#import "NuRegex.h"
#import "NuBridge.h"
#import "NuClass.h"
#import "NuEnumerable.h"
#import <unistd.h>

#import "NuException.h"

#import "NuVersion.h"

id Nu__null = 0;

bool nu_valueIsTrue(id value)
{
    bool result = value && (value != Nu__null);
    if (result && nu_objectIsKindOfClass(value, [NSNumber class])) {
        if ([value doubleValue] == 0.0)
            result = false;
    }
    return result;
}

@interface NuApplication : NSObject
{
    NSMutableArray *arguments;
}

@end

static NuApplication *_sharedApplication = 0;

@implementation NuApplication
+ (NuApplication *) sharedApplication
{
    if (!_sharedApplication)
        _sharedApplication = [[NuApplication alloc] init];
    return _sharedApplication;
}

- (void) setArgc:(int) argc argv:(const char *[])argv startingAtIndex:(int) start
{
    arguments = [[NSMutableArray alloc] init];
    int i;
    for (i = start; i < argc; i++) {
        [arguments addObject:[NSString stringWithCString:argv[i] encoding:NSUTF8StringEncoding]];
    }
}

- (NSArray *) arguments
{
    return arguments;
}

@end

static void write_arguments(int argc, char *argv[])
{
    NSLog(@"launched with arguments");
    int i;
    for (i = 0; i < argc; i++) {
        NSLog(@"argv[%d]: %s", i, argv[i]);
    }
}

static void NuMain_exceptionHandler(NSException* e)
{
    printf("%s\n", [[e dump] cStringUsingEncoding:NSUTF8StringEncoding]);
    exit(1);
}

int NuMain(int argc, const char *argv[])
{
	#ifdef IPHONE
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	#endif

    NuInit();

#if 0
    NSSetUncaughtExceptionHandler(&NuMain_exceptionHandler);
    [[NSExceptionHandler defaultExceptionHandler]
        setExceptionHandlingMask:(    NSHandleUncaughtExceptionMask
                                    | NSHandleUncaughtSystemExceptionMask
                                    | NSHandleUncaughtRuntimeErrorMask
                                    | NSHandleTopLevelExceptionMask
                                    | NSHandleOtherExceptionMask)];
#endif

    @try
    {
        @autoreleasepool {

        // first we try to load main.nu from the application bundle.
        NSString *main_path = [[NSBundle mainBundle] pathForResource:@"main" ofType:@"nu"];
        if (main_path) {
            NSString *main_nu = [NSString stringWithContentsOfFile:main_path encoding:NSUTF8StringEncoding error:nil];
            if (main_nu) {
                NuParser *parser = [[NuParser alloc] init];
                id script = [parser parse:main_nu asIfFromFilename:[main_nu cStringUsingEncoding:NSUTF8StringEncoding]];
                [parser eval:script];
                [parser release];
                //[pool release];
                return 0;
            }
        }
        // if that doesn't work, use the arguments to decide what to execute
        else if (argc > 1) {
            NuParser *parser = [[NuParser alloc] init];
            id script, result;
            bool didSomething = false;
            bool goInteractive = false;
            int i = 1;
            bool fileEvaluated = false;           // only evaluate one filename
            while ((i < argc) && !fileEvaluated) {
                if (!strcmp(argv[i], "-e")) {
                    i++;
                    script = [parser parse:[NSString stringWithCString:argv[i] encoding:NSUTF8StringEncoding]];
                    result = [parser eval:script];
                    didSomething = true;
                }
                else if (!strcmp(argv[i], "-f")) {
                    i++;
                    script = [parser parse:[NSString stringWithFormat:@"(load \"%s\")", argv[i]] asIfFromFilename:argv[i]];
                    result = [parser eval:script];
                }
                else if (!strcmp(argv[i], "-v")) {
                    printf("Nu %s (%s)\n", NU_VERSION, NU_RELEASE_DATE);
                    didSomething = true;
                }
                else if (!strcmp(argv[i], "-i")) {
                    goInteractive = true;
                }
                else {
                    // collect the command-line arguments
                    [[NuApplication sharedApplication] setArgc:argc argv:argv startingAtIndex:i+1];
                    id string = [NSString stringWithContentsOfFile:[NSString stringWithCString:argv[i] encoding:NSUTF8StringEncoding] encoding:NSUTF8StringEncoding error:NULL];
                    if (string) {
                        id script = [parser parse:string asIfFromFilename:argv[i]];
                        [parser eval:script];
                        fileEvaluated = true;
                    }
                    else {
                        // complain somehow. Throw an exception?
                        NSLog(@"Error: can't open file named %s", argv[i]);
                    }
                    didSomething = true;
                }
                i++;
            }
#ifndef IPHONE
            if (!didSomething || goInteractive)
                [parser interact];
#endif
            [parser release];

            return 0;
        }
        // if there's no file, run at the terminal
        else {
            if (!isatty(stdin->_file))	   
            {
                NuParser *parser = [[NuParser alloc] init];
                id string = [[NSString alloc] initWithData:[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
                id script = [parser parse:string asIfFromFilename:"stdin"];
                [parser eval:script];
                [parser release];
                //[pool release];
            }
            else {
               // [pool release];
#ifndef IPHONE
                return [NuParser main];
#endif
            }
        }
    }
    }
	@catch (NuException* nuException)
    {
        printf("%s\n", [[nuException dump] cStringUsingEncoding:NSUTF8StringEncoding]);
	}
    @catch (id exception)
    {
        NSLog(@"Terminating due to uncaught exception (below):");
        NSLog(@"%@: %@", [exception name], [exception reason]);
    }

	#ifdef IPHONE
    [pool release];
	#endif
    return 0;
}

static void transplant_nu_methods(Class destination, Class source)
{
    if (!nu_copyInstanceMethod(destination, source, @selector(evalWithArguments:context:)))
        NSLog(@"method copy failed");
    if (!nu_copyInstanceMethod(destination, source, @selector(sendMessage:withContext:)))
        NSLog(@"method copy failed");
    if (!nu_copyInstanceMethod(destination, source, @selector(stringValue)))
        NSLog(@"method copy failed");
    if (!nu_copyInstanceMethod(destination, source, @selector(evalWithContext:)))
        NSLog(@"method copy failed");
    if (!nu_copyInstanceMethod(destination, source, @selector(handleUnknownMessage:withContext:)))
        NSLog(@"method copy failed");
}

void NuInit()
{
    static int initialized = 0;
    if (!initialized) {
        initialized = 1;

        Nu__null = [NSNull null];

        // add enumeration to collection classes
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [NSArray include: [NuClass classWithClass:[NuEnumerable class]]];
        [NSSet include: [NuClass classWithClass:[NuEnumerable class]]];
        [NSString include: [NuClass classWithClass:[NuEnumerable class]]];
        [pool drain];

        #ifndef IPHONE
        // Copy some useful methods from NSObject to NSProxy.
        // Their implementations are identical; this avoids code duplication.
        transplant_nu_methods([NSProxy class], [NSObject class]);

        void nu_swizzleContainerClasses();
        nu_swizzleContainerClasses();

        #ifndef MININUSH
        // Load some standard files
        // Warning: since these loads are performed without a context, the non-global symbols defined in them
        // will not be available to other Nu scripts or at the console.  These loads should only be used
        // to set globals and to make changes to information stored in the ObjC runtime.
        [Nu loadNuFile:@"nu"            fromBundleWithIdentifier:@"nu.programming.framework" withContext:nil];
        [Nu loadNuFile:@"bridgesupport" fromBundleWithIdentifier:@"nu.programming.framework" withContext:nil];
        [Nu loadNuFile:@"cocoa"         fromBundleWithIdentifier:@"nu.programming.framework" withContext:nil];
        [Nu loadNuFile:@"help"          fromBundleWithIdentifier:@"nu.programming.framework" withContext:nil];
        #endif
        #endif

        
    }
}

// Helpers for programmatic construction of Nu code.

id _nunull()
{
    return [NSNull null];
}

id _nustring(const char *string)
{
    return [NSString stringWithCString:string encoding:NSUTF8StringEncoding];
}

id _nustring_with_length(const char *string, int length)
{
	NSData *data = [NSData dataWithBytes:string length:length];
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

id _nudata(const void *bytes, int length)
{
	return [NSData dataWithBytes:bytes length:length];
}

id _nusymbol(const char *string)
{
    return [[NuSymbolTable sharedSymbolTable] symbolWithCString:string];
}

id _nusymbol_with_length(const char *string, int length)
{
	return [[NuSymbolTable sharedSymbolTable] symbolWithString:_nustring_with_length(string, length)];
}

id _nunumberd(double d)
{
    return [NSNumber numberWithDouble:d];
}

id _nucell(id car, id cdr)
{
    return [NuCell cellWithCar:car cdr:cdr];
}

id _nuregex(const char *pattern, int options)
{
    return [NSRegularExpression regexWithPattern:_nustring(pattern) options:options];
}

id _nuregex_with_length(const char *pattern, int length, int options)
{
    return [NSRegularExpression regexWithPattern:_nustring_with_length(pattern, length) options:options];
}

id _nulist(id firstObject, ...)
{
    id list = nil;
    id eachObject;
    va_list argumentList;
    if (firstObject) {
        // The first argument isn't part of the varargs list,
        // so we'll handle it separately.
        list = [[[NuCell alloc] init] autorelease];
        [list setCar:firstObject];
        id cursor = list;
        va_start(argumentList, firstObject);
        // Start scanning for arguments after firstObject.
        // As many times as we can get an argument of type "id"
        // that isn't nil, add it to self's contents.
        while ((eachObject = va_arg(argumentList, id))) {
            [cursor setCdr:[[[NuCell alloc] init] autorelease]];
            cursor = [cursor cdr];
            [cursor setCar:eachObject];
        }
        va_end(argumentList);
    }
    return list;
}

@implementation Nu
+ (id<NuParsing>) parser
{
    return [[[NuParser alloc] init] autorelease];
}

+ (id<NuParsing>) sharedParser
{
    static NuParser *sharedParser = nil;
    if (!sharedParser) {
        sharedParser = [[NuParser alloc] init];
    }
    return (id<NuParsing>) sharedParser;
}

+ (int) sizeOfPointer
{
    return sizeof(void *);
}

+ (BOOL) loadNuFile:(NSString *) fileName fromBundleWithIdentifier:(NSString *) bundleIdentifier withContext:(NSMutableDictionary *) context
{
    BOOL success = NO;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSBundle *bundle = [NSBundle bundleWithIdentifier:bundleIdentifier];
    NSString *filePath = [bundle pathForResource:fileName ofType:@"nu"];
    if (filePath) {
        NSString *fileNu = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if (fileNu) {
            id parser = [Nu parser];
            id script = [parser parse:fileNu asIfFromFilename:[filePath cStringUsingEncoding:NSUTF8StringEncoding]];
            if (!context) context = [parser context];
            [script evalWithContext:context];
            success = YES;
        }
    }
    else {
        if ([bundleIdentifier isEqual:@"nu.programming.framework"]) {
            // try to read it if it's baked in

            @try
            {
                id baked_function = [NuBridgedFunction functionWithName:[NSString stringWithFormat:@"baked_%@", fileName] signature:@"@"];
                id baked_code = [baked_function evalWithArguments:nil context:nil];
                if (!context) {
                    id parser = [Nu parser];
                    context = [parser context];
                }
                [baked_code evalWithContext:context];
                success = YES;
            }
            @catch (id exception)
            {
                success = NO;
            }
        }
        else {
            success = NO;
        }
    }
    [pool release];
    return success;
}

@end
