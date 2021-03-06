//
//  OTXDisassemblyScanner.m
//  otxProcessor
//
//  Created by Scott Morrison on 10-05-08.
//  Copyright 2010 Indev Software, Inc. All rights reserved.
//

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     1. Redistributions of source code must retain the above copyright
//          notice, this list of conditions and the following disclaimer.
//     2. Redistributions in binary form must reproduce the above copyright
//          notice, this list of conditions and the following disclaimer in the
//          documentation and/or other materials provided with the distribution.
//     3. Neither the name of Indev Software nor the
//          names of its contributors may be used to endorse or promote products
//          derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY INDEV SOFTWARE ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL INDEV SOFTWARE BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#import "OTXDisassemblyScanner.h"
#import "Mach_O_scopeAppDelegate.h"

@interface NSString (OTXDisassemblyScanner)
-(NSDictionary *) scanBlockInvocationMethodName;
-(NSDictionary *) scanCFunctionName;
-(NSDictionary *) scanClassMethodName;
-(NSDictionary *) scanDisassembly;

@end



@implementation OTXDisassemblyScanner

@synthesize database, delegate, bundlePath,cancelImport;

- (id)initWithDelegate: (id)anObject bundle:(NSString*)aBundlePath andDatabase:(MOSDatabase *)aDatabase{
	self = [super init];
	if (self){
		self.delegate = anObject;
		self.bundlePath = aBundlePath;
		self.database = aDatabase;
	}
	return self;
}

-(void)dealloc{
	self.delegate = nil;
	self.bundlePath = nil;
	self.database = nil;
	[super dealloc];
}

- (void) importFromOtx: (NSString *) tempOtxFile  classdump:(NSString*)tempClassDumpFile{
	// next  from file
    NSMutableDictionary * interfaces = [[NSMutableDictionary alloc] init];
    NSMutableDictionary * structs = [[NSMutableDictionary alloc] init];
    if (tempClassDumpFile){
        
        NSString * classDump = [[NSString alloc] initWithContentsOfFile:tempClassDumpFile encoding:NSASCIIStringEncoding error:nil];
         NSMutableString * currentStruct = nil;
         NSString * currentItemName = nil;
         NSMutableString * currentInterface = nil;
         NSArray * classDumpArray = [classDump componentsSeparatedByString:@"\n"];
         for (NSString * line in classDumpArray){
        // [classDump enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) { // this crashes!
 
             if (currentStruct == nil && currentInterface==nil){
                 if ( [line hasPrefix:@"struct"]){
                     //NSLog (@"found  %@",line); 
                     currentStruct = [[NSMutableString alloc] initWithString: line];
                     currentItemName = [[[line componentsSeparatedByString:@" "] objectAtIndex:1] copy];
                 }
                 if ( [line hasPrefix:@"@interface"]){
                     currentInterface = [[NSMutableString  alloc] initWithString: line];
                     //NSLog (@"found  %@",line);
                     NSArray * interfaceParts = [line componentsSeparatedByString:@" "];
                     currentItemName = [[interfaceParts objectAtIndex:1] copy];
                     
                 }
            }
            else if (currentStruct){
                [currentStruct appendFormat:@"\n%@",line];
                if ([line hasPrefix:@"};"]){
                    [structs setObject:currentStruct forKey:currentItemName];
                     //NSLog (@"end %@",currentItemName);
                    [currentStruct release];
                    currentStruct = nil;
                    [currentItemName release];
                    currentItemName = nil;
                }
            }
            else if (currentInterface){
                [currentInterface appendFormat:@"\n%@",line];
                if ([line hasPrefix:@"@end"]){
                    NSMutableString * existingInterface = [[interfaces objectForKey: currentItemName] mutableCopy];
                    if (existingInterface) 
                        [existingInterface appendFormat: @"\n\n%@",currentInterface];
                    else 
                       existingInterface = [[NSMutableString alloc] initWithString:currentInterface];
                    
                    [interfaces setObject:existingInterface forKey:currentItemName];
                    [existingInterface release];
                   // NSLog (@"end %@",currentItemName);
                    [currentInterface release];
                    currentInterface = nil;

                    [currentItemName release];
                    currentItemName = nil;
                  }
            }             
         }
         
        [classDump release];

        
        
    }
    NSString * dis = [[NSString alloc] initWithContentsOfFile:tempOtxFile encoding:NSASCIIStringEncoding error:nil];
	NSArray * disArray = [[dis componentsSeparatedByString:@"\n"] copy];
	[dis release];
	
	NSInteger counter = 0;
	NSMutableDictionary * classIDs =[[NSMutableDictionary alloc] init];
	NSString * currentClass = nil;
	NSInteger currentMethodID = 0;
	NSInteger currentOpID = 0;
	
	[self.database dropStructure];
	[self.database createStructure];
	
	// use a temporary table to speed up import  by writing dissassembly to memory first and then to write  temporary table to the persistent store after interval (10000 lines)
	
	[self.database executeUpdate:@"create temporary table tempOperations (operationID INTEGER PRIMARY KEY,"
										 "methodID integer Key,"
										 "offset integer,"
										 "address text,"
										 "bytes text,"
										 "opcode test,"
										 "data text,"
										 "notes text,"
										 "symbols text,"
										 "UNIQUE (operationID))"];
	
	NSInteger totalCount = [disArray count];
	if ([self.delegate respondsToSelector:@selector(updateProgressIndicatorWithCount:)]){
		[self.delegate performSelectorOnMainThread:@selector(updateProgressIndicatorWithCount:)
							   withObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:0], @"current",
										   [NSNumber numberWithInteger:totalCount], @"total",nil]  
							waitUntilDone:NO];
	}
	
	for (NSString *line in disArray){
		
		if([line length] >0){
			NSString * methodType = nil;
			if ([line hasPrefix:@"+("] || [line hasPrefix:@"-("] || [line hasPrefix:@"_"] || [line hasPrefix:@"Anon"]){
				NSDictionary * info = nil;
				if ([line hasPrefix:@"+("]){  
					methodType = @"+";
					info = [line scanClassMethodName];
				}
				else if ([line hasPrefix:@"-("]){
					methodType = @"-";
					info = [line scanClassMethodName];
				}
				else if ([line hasPrefix:@"___+["]){
					methodType = @"^+";
					info = [line scanBlockInvocationMethodName];
				}
				else if ([line hasPrefix:@"___-["]){
					methodType = @"^-";
					info = [line scanBlockInvocationMethodName];
				}
					// class method
				else if ([line hasPrefix:@"_"] || [line hasPrefix:@"Anon"]){// c function call
					info = [line scanCFunctionName];
					methodType = @"C";
				}
				currentClass= [info objectForKey:@"className"];
				
				
				NSString * classID = [classIDs objectForKey:currentClass];
				if (!classID){
					//TODO: integrate with ClassDump - have MOS spin off a task for classdumping the currentCass
					// need ivarList
					// properties 
					// superclass
                    NSString *classDump = [interfaces objectForKey:currentClass];
                    if (!classDump) classDump=@"";
					[self.database executeQueryWithParameters:@"insert into Classes (className,classDump) values (?,?)",currentClass,classDump,nil];
					EGODatabaseResult* result = [self.database executeQueryWithParameters:@"select * from Classes where className == ?",currentClass,nil];
					if ([result count]){
						classID = [[result rowAtIndex:0] stringForColumnIndex:0];
						[classIDs setObject:classID forKey:currentClass];
					}
				}		
				currentMethodID++;
				[self.database executeQueryWithParameters:@"insert into Methods (methodID, classID,rawInfo, methodName,MethodType,returnType) values (?,?,?,?,?,?)",
												[NSNumber numberWithInteger:currentMethodID],
												classID,
												line,
												[info objectForKey:@"method"],
												methodType,
												[info objectForKey:@"returnType"],
											nil];
			}
			else if ([[line substringToIndex:1] isEqualToString:@" "]|| [[line substringToIndex:1] isEqualToString:@"\t"]){				
				NSDictionary * opDict = [line scanDisassembly];
				currentOpID++;
				[self.database executeQueryWithParameters:@"insert into tempOperations (operationID, methodID, offset,address,bytes,opcode,data,symbols)"
													"values (?,?,?,?,?,?,?,?)",
															 [NSNumber numberWithInteger:currentOpID],
															 [NSNumber numberWithInteger:currentMethodID],
															 [opDict objectForKey:@"offset"],
															 [opDict objectForKey:@"address"],
															 [opDict objectForKey:@"bytes"],
															 [opDict objectForKey:@"operation"],
															 [opDict objectForKey:@"data"],
															 [opDict objectForKey:@"symbols"],
															 nil];
					
				
			}
			else if ([line hasPrefix:@"Anon???"]){
				// skip this line.
				// note - Anon??? headers will reset the ofsets in the disassembly
			}
			
		}
		//if (counter  > 2500)break;
		if (++counter % 10000==0) {
				
			// write data in temporary table to the persistent store.
			[self.database executeUpdate:@"insert into Operations select * from tempOperations"];
			[self.database executeUpdate:@"drop table tempOperations"];
			[self.database executeUpdate:@"create temporary table tempOperations (operationID INTEGER PRIMARY KEY,"
																				 "methodID integer Key,"
																				 "offset integer,"
																				 "address text,"
																				 "bytes text,"
																				 "opcode test,"
																				 "data text,"
																				 "notes text,"
																				 "symbols text,"
																				 "UNIQUE (operationID))"];
			
			// let the delegate know to update progress on the main thread.
			if ([self.delegate respondsToSelector:@selector(updateProgressIndicatorWithCount:)]){
				[self.delegate performSelectorOnMainThread:@selector(updateProgressIndicatorWithCount:)
												withObject:[NSDictionary dictionaryWithObjectsAndKeys:
																	[NSNumber numberWithInteger:counter],		@"current",
																	[NSNumber numberWithInteger:totalCount],	@"total",
																	nil]  
											 waitUntilDone:NO];
			}
			
		}
		if (cancelImport) break;
	}
    [structs release];
    [interfaces release];
	[classIDs release];
	[disArray release];
	[self.database executeUpdate:@"insert into Operations select * from tempOperations "];
	[self.database executeUpdate:@"drop table tempOperations"];
	
	if ([self.delegate respondsToSelector:@selector(importCompleteWithResult:)]){
		[self.delegate performSelectorOnMainThread:@selector(importCompleteWithResult:)
										withObject:[NSNumber numberWithBool:!(self.cancelImport)]
							waitUntilDone:NO];
	}

}


-(NSString *) _dumpOTX{
    NSString * tempOtxFile = [NSTemporaryDirectory() stringByAppendingString: [[self.bundlePath lastPathComponent] stringByAppendingString:@".otxdump"]];
	
	NSTask * otxTask = [[NSTask  alloc]  init];			
	NSString * pathToOtx = [[NSBundle bundleForClass: [self class]] pathForResource:@"otx" ofType:nil];
    
    
    
    NSArray* args = [NSArray arrayWithObjects:@"-arch",
					 [[NSApp delegate] saveArchitecture],
					 self.bundlePath, nil];
    
    
	// create the file with empty content to be able to create a valid file handle
	[[NSData data] writeToFile:tempOtxFile options:0 error:nil];
	NSFileHandle* writer = [NSFileHandle fileHandleForWritingAtPath:tempOtxFile];
    
	if (writer)
	{
		[otxTask setStandardOutput:writer];
	}
	else
	{
		NSLog(@"could not create file handle");
	}
	[otxTask setLaunchPath:pathToOtx];
	[otxTask setArguments:args];
	
	[otxTask launch];
	
	[otxTask waitUntilExit];
	
	[otxTask release];
    
    return tempOtxFile;
    
}

-(NSString *)_dumpClassDump{
    NSString * tempClassDumpFile = [NSTemporaryDirectory() stringByAppendingString: [[self.bundlePath lastPathComponent] stringByAppendingString:@".classdump"]];
    NSTask * classDumpTask = [[NSTask  alloc]  init];		
    NSString * pathToClassDump = [[NSBundle bundleForClass: [self class]] pathForResource:@"class-dump" ofType:nil];
    NSArray* classDumpArgs = [NSArray arrayWithObjects:@"--arch",
                              [[NSApp delegate] saveArchitecture],
                              @"-a", // show instance Variable offsets
                              @"-A", // show implementation addresses
                              @"-s", // sort classes and Categories
                              //@"-S", // sortMethods
                              self.bundlePath, nil];    
    
	// create the file with empty content to be able to create a valid file handle
	[[NSData data] writeToFile:tempClassDumpFile options:0 error:nil];
	NSFileHandle* writer = [NSFileHandle fileHandleForWritingAtPath:tempClassDumpFile];
    
	if (writer)
	{
		[classDumpTask setStandardOutput:writer];
	}
	else
	{
		NSLog(@"could not create file handle");
	}
	[classDumpTask setLaunchPath:pathToClassDump];
	[classDumpTask setArguments:classDumpArgs];
	
	[classDumpTask launch];
	
	[classDumpTask waitUntilExit];
	
	[classDumpTask release];

    return tempClassDumpFile;
    
}
-(void)_backgroundImportBundle
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	
	// first call OTX to do its magic on the bundle and to write the otx dump to a file in the temporary directory.

  

    NSString * tempOtxFilePath= [self _dumpOTX];
    NSString * tempClassDumpFilePath= [self _dumpClassDump];
    
	[self importFromOtx: tempOtxFilePath classdump:tempClassDumpFilePath];

	[pool release];
	
	
	
}

-(void)_backgroundImportOtx
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	[self importFromOtx: self.bundlePath classdump:nil];
	
	[pool release];
	
	
}





@end

@implementation NSString (OTXDisassemblyScanner)

-(NSDictionary *) scanCFunctionName{
	// a cFunction will appears with a _ prefix and ends in a : (with no class inforation)
	// for example:
	//		_MFLookupLocalizedString:
	//
	NSString *line = self; 
	NSScanner * lineScanner = [NSScanner scannerWithString:line];
	NSString *methodName = nil;
	[lineScanner scanUpToString:@":" intoString:&methodName];
	
	NSDictionary *resultDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
												  @"unknown",			@"returnType",
												  @"_C Functions",		@"className", 
												  methodName,			@"method", 
												  nil];
	return resultDictionary;
	
}
-(NSDictionary *) scanClassMethodName {
	NSString *line = self; 
	NSScanner * lineScanner = [NSScanner scannerWithString:line];
	NSString * returnType = nil;
	[lineScanner scanUpToString:@"(" intoString:nil];
	[lineScanner scanUpToString:@"[" intoString:&returnType];
	[lineScanner scanString:@"[" intoString:nil];
	NSString *className = nil;
	[lineScanner scanUpToString:@" " intoString:&className];
	
	// see if this is a category/
	
	NSScanner * nameScanner = [NSScanner scannerWithString:className];
	[nameScanner scanUpToString:@"(" intoString:&className];
	
	[lineScanner scanString:@" " intoString:nil];
	NSString *methodName = nil;
	[lineScanner scanUpToString:@"]" intoString:&methodName];
	
	NSDictionary *resultDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									  returnType,@"returnType",className, @"className", methodName, @"method", nil];
	return resultDictionary;
}
-(NSDictionary *) scanBlockInvocationMethodName{
	NSString *line = self; 
	NSScanner * lineScanner = [NSScanner scannerWithString:line];
	[lineScanner scanUpToString:@"[" intoString:nil];
	[lineScanner scanString:@"[" intoString:nil];
	NSString *className = nil;
	[lineScanner scanUpToString:@" " intoString:&className];
	[lineScanner scanString:@" " intoString:nil];
	NSString *methodName = nil;
	[lineScanner scanUpToString:@"]" intoString:&methodName];
	[lineScanner scanString:@"]" intoString:nil];
	NSString *blockInvocation = nil;
	[lineScanner scanUpToString:@":" intoString:&blockInvocation];
	
	NSDictionary *resultDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
											  @"unknown",		@"returnType",
											  className,		@"className", 
											  [methodName stringByAppendingString:blockInvocation], @"method",
									  nil];
	return resultDictionary;
}

-(NSDictionary *)scanDisassembly{
	NSString *line = self; 
	NSScanner * lineScanner = [NSScanner scannerWithString:line];
	[lineScanner scanUpToString:@"+" intoString:nil];
	//[lineScanner scanString:@"+" intoString:nil];
	NSString * offset = nil;
	[lineScanner scanUpToString:@" " intoString:&offset];
	//[lineScanner scanString:@"\t" intoString:nil];
	
	NSString * address = nil;
	[lineScanner scanUpToString:@"  " intoString:&address];
	//[lineScanner scanString:@"  " intoString:nil];
	
	NSString * bytes = nil;
	NSString * op = nil;
	NSString * data = nil;
	NSString * note = nil;
	[lineScanner scanUpToString:@" " intoString:&bytes];
	[lineScanner scanUpToString:@" " intoString:&op];
	[lineScanner scanUpToString:@"  " intoString:&data];
	[lineScanner scanUpToString:@"\n" intoString:&note];
	
	if (!data) data=@"";
	if (!note) note = @"";
	
	//NSString * resultString = [NSString stringWithFormat:@"o:%@ a:%@ b:%@ oo:%@ d:%@ n:%@",offset,address,bytes,op,data,note];
	//NSString * resultString = [NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@\t%@",offset,address,bytes,op,data,note];
	
	NSDictionary *resultDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
									  [NSNumber numberWithInteger:[offset integerValue]],@"offset",
									  address, @"address", 
									  bytes, @"bytes", 
									  op, @"operation",
									  data, @"data",
									  note, @"symbols", nil];
	
	return resultDictionary;
}


@end

