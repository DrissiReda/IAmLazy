//
//	IALManager.m
//	IAmLazy
//
//	Created by Lightmann during COVID-19
//

#import "IALManager.h"
#import "Common.h"

@implementation IALManager

+(instancetype)sharedInstance{
	static dispatch_once_t p = 0;
	__strong static IALManager* sharedInstance = nil;
	dispatch_once(&p, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

#pragma mark Backup

-(void)makeTweakBackupWithFilter:(BOOL)filter{
	// reset errors
	[self setEncounteredError:NO];

	// make note of start time
	[self setStartTime:[NSDate date]];

	// check if Documents/ has root ownership (it shouldn't)
	if([[NSFileManager defaultManager] isWritableFileAtPath:@"/var/mobile/Documents/"] == 0){
		NSString *reason = @"/var/mobile/Documents is not writeable. \n\nPlease ensure that the directory's owner is mobile and not root.";
		[self popErrorAlertWithReason:reason];
		return;
	}

	// check for old tmp files
	if([[NSFileManager defaultManager] fileExistsAtPath:tmpDir]){
		[self cleanupTmp];
	}

	// get all packages
	if(!filter){
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"null"];
		NSArray *allPackages = [self getAllPackages];
		if(![allPackages count]){
			NSString *reason = @"Failed to generate list of installed packages! \n\nPlease try again.";
			[self popErrorAlertWithReason:reason];
			return;
		}
		[self setPackages:allPackages];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"0"];
	}

	// get user packages (filter out bootstrap packages)
	else{
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"null"];
		NSArray *userPackages = [self getUserPackages];
		if(![userPackages count]){
			NSString *reason = @"Failed to generate list of user packages! \n\nPlease try again.";
			[self popErrorAlertWithReason:reason];
			return;
		}
		[self setPackages:userPackages];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"0"];
	}

	// make fresh tmp directory
	if(![[NSFileManager defaultManager] fileExistsAtPath:tmpDir]){
		NSError *error = NULL;
		[[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:&error];
		if(error){
			NSString *reason = [NSString stringWithFormat:@"Failed to create %@. \n\nError: %@", tmpDir, error.localizedDescription];
			[self popErrorAlertWithReason:reason];
			return;
		}
	}

	// gather bits for packages
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"0.7"];
	[self gatherPackageFiles];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"1"];

	// make backup and log dirs if they don't exist already
	if(![[NSFileManager defaultManager] fileExistsAtPath:logDir]){
		NSError *error = NULL;
		[[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:&error];
		if(error){
			NSString *reason = [NSString stringWithFormat:@"Failed to create %@. \n\nError: %@", logDir, error.localizedDescription];
			[self popErrorAlertWithReason:reason];
			return;
		}
	}

	// build debs from bits
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"1.7"];
	[self buildDebs];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"2"];

	// for unfiltered backups, create hidden file specifying the bootstrap it was created on
	if(!filter) [self makeBootstrapFile];

	// make archive of all packages
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"2.7"];
	[self makeTarballWithFilter:filter];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"3"];

	// make note of end time
	[self setEndTime:[NSDate date]];
}

-(NSArray *)getAllPackages{
	NSMutableArray *allPackages = [NSMutableArray new];

	NSString *output = [self executeCommandWithOutput:@"dpkg-query -Wf '${Package;-50}${Priority}\n'"];
	NSArray *lines = [output componentsSeparatedByString:@"\n"];

	NSPredicate *thePredicate = [NSPredicate predicateWithFormat:@"SELF endswith 'required'"]; // filter out local packages
	NSPredicate *theAntiPredicate = [NSCompoundPredicate notPredicateWithSubpredicate:thePredicate]; // find the opposite of ^
	NSArray *packages = [lines filteredArrayUsingPredicate:theAntiPredicate];

	for(NSString *line in packages){
		// filter out IAmLazy since it'll be installed by the user anyway
		if([line length] && ![line containsString:@"me.lightmann.iamlazy"]){
			NSArray *bits = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if([bits count]) [allPackages addObject:bits.firstObject];
		}
	}

	return allPackages;
}

-(NSArray *)getUserPackages{
	NSMutableArray *userPackages = [NSMutableArray new];

	NSString *output = [self executeCommandWithOutput:@"dpkg-query -Wf '${Package;-50}${Maintainer}\n'"];
	NSArray *lines = [output componentsSeparatedByString:@"\n"];

	NSPredicate *predicate1 = [NSPredicate predicateWithFormat:@"SELF contains 'Sam Bingner'"]; // filter out bootstrap packages
	NSPredicate *predicate2 = [NSPredicate predicateWithFormat:@"SELF contains 'Jay Freeman (saurik)'"];
	NSPredicate *predicate3 = [NSPredicate predicateWithFormat:@"SELF contains 'CoolStar'"];
	NSPredicate *predicate4 = [NSPredicate predicateWithFormat:@"SELF contains 'Hayden Seay'"];
	NSPredicate *predicate5 = [NSPredicate predicateWithFormat:@"SELF contains 'Cameron Katri'"];
	NSPredicate *predicate6 = [NSPredicate predicateWithFormat:@"SELF contains 'Procursus Team'"];
	NSPredicate *thePredicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[predicate1, predicate2, predicate3, predicate4, predicate5, predicate6]];  // combine with "or"
	NSPredicate *theAntiPredicate = [NSCompoundPredicate notPredicateWithSubpredicate:thePredicate]; // find the opposite of ^
	NSArray *packages = [lines filteredArrayUsingPredicate:theAntiPredicate];

	for(NSString *line in packages){
		// filter out IAmLazy since it'll be installed by the user anyway
		if([line length] && ![line containsString:@"me.lightmann.iamlazy"]){
			NSArray *bits = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if([bits count]) [userPackages addObject:bits.firstObject];
		}
	}

	return userPackages;
}

-(void)gatherPackageFiles{
	for(NSString *package in self.packages){
		NSMutableArray *genericFiles = [NSMutableArray new];
		NSMutableArray *directories = [NSMutableArray new];

		// get generic files and directories and sort into respective arrays
		NSString *output = [self executeCommandWithOutput:[NSString stringWithFormat:@"dpkg-query -L %@", package]];
		NSArray *lines = [output componentsSeparatedByString:@"\n"];
		for(NSString *line in lines){
			if(![line length] || [line isEqualToString:@"/."]){
				continue; // disregard
			}

			NSError *readError = NULL;
			NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:line error:&readError];
			if(readError){
				NSLog(@"[IAmLazyLog] Failed to get attributes for %@! Error: %@", line, readError.localizedDescription);
				continue;
			}

			NSString *type = [fileAttributes fileType];

			// check to see how many times the current filepath is present in the list output
			// shoutout Cœur on StackOverflow for this efficient code (https://stackoverflow.com/a/57869286)
			int count = [[NSMutableString stringWithString:output] replaceOccurrencesOfString:line withString:line options:NSLiteralSearch range:NSMakeRange(0, output.length)];

			if(count == 1){ // this is good, means it's unique!
				if([type isEqualToString:@"NSFileTypeDirectory"]){
					[directories addObject:line];
				}
				else{
					[genericFiles addObject:line];
				}
			}
			else{
				// sometimes files will have similar names (e.g., /usr/bin/zip, /usr/bin/zipcloak, /usr/bin/zipnote, /usr/bin/zipsplit)
				// though /usr/bin/zip will have a count > 1, since it's present in the other filepaths, we want to avoid disregarding it
				// since it's a valid file. instead, we want to disregard all dirs and symlinks that don't lead to files as they're simply
				// part of the package's list structure. in the above example, that would mean disregarding /usr and /usr/bin
				if(![type isEqualToString:@"NSFileTypeDirectory"] && ![type isEqualToString:@"NSFileTypeSymbolicLink"]){
					[genericFiles addObject:line];
				}
				else if([type isEqualToString:@"NSFileTypeSymbolicLink"]){
					// want to grab any symlniks that lead to files, but ignore those that lead to dirs
					// this will traverse any links and check for the existence of a file at the link's final destination
					BOOL isDir = NO;
					if([[NSFileManager defaultManager] fileExistsAtPath:line isDirectory:&isDir] && !isDir){
						[genericFiles addObject:line];
					}
				}
			}
		}

		// get DEBIAN files (e.g., pre/post scripts) and put into an array
		NSString *output2 = [self executeCommandWithOutput:[NSString stringWithFormat:@"dpkg-query -c %@", package]];
		NSArray *lines2 = [output2 componentsSeparatedByString:@"\n"];
		NSPredicate *thePredicate = [NSPredicate predicateWithFormat:@"SELF contains '.md5sums'"]; // dpkg generates this dynamically at installation
		NSPredicate *theAntiPredicate = [NSCompoundPredicate notPredicateWithSubpredicate:thePredicate]; // find the opposite of ^
		NSArray *debianFiles = [lines2 filteredArrayUsingPredicate:theAntiPredicate];

		// put the files we want to copy into lists for easier writing
		NSString *gFilePaths = [[genericFiles valueForKey:@"description"] componentsJoinedByString:@"\n"];
		if(![gFilePaths length]){
			NSLog(@"[IAmLazyLog] gFilePaths list is blank for %@!", package);
		}

		NSString *dFilePaths = [[debianFiles valueForKey:@"description"] componentsJoinedByString:@"\n"];
		if(![dFilePaths length]){
			NSLog(@"[IAmLazyLog] dFilePaths list is blank for %@!", package);
		}

		// this is nice because it overwrites the file's content, unlike the write method from NSFileManager
		NSError *writeError = NULL;
		[gFilePaths writeToFile:gFilesToCopy atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
		if(writeError){
			NSLog(@"[IAmLazyLog] Failed to write gFilePaths to %@ for %@! Error: %@", gFilesToCopy, package, writeError.localizedDescription);
			continue;
		}

		NSError *writeError2 = NULL;
		[dFilePaths writeToFile:dFilesToCopy atomically:YES encoding:NSUTF8StringEncoding error:&writeError2];
		if(writeError2){
			NSLog(@"[IAmLazyLog] Failed to write dFilePaths to %@ for %@! Error: %@", dFilesToCopy, package, writeError2.localizedDescription);
			continue;
		}

		NSString *tweakDir = [tmpDir stringByAppendingPathComponent:package];

		// make dir to hold stuff for the tweak
		if(![[NSFileManager defaultManager] fileExistsAtPath:tweakDir]){
			NSError *error = NULL;
			[[NSFileManager defaultManager] createDirectoryAtPath:tweakDir withIntermediateDirectories:YES attributes:nil error:&error];
			if(error){
				NSLog(@"[IAmLazyLog] Failed to create %@! Error: %@", tweakDir, error.localizedDescription);
				continue;
			}
		}

		// again, this is nice because it overwrites the file's content, unlike the write method from NSFileManager
		NSError *writeError3 = NULL;
		[tweakDir writeToFile:targetDir atomically:YES encoding:NSUTF8StringEncoding error:&writeError3];
		if(writeError3){
			NSLog(@"[IAmLazyLog] Failed to write tweakDir to %@ for %@! Error: %@", targetDir, package, writeError3.localizedDescription);
			continue;
		}

		[self makeSubDirectories:directories inDirectory:tweakDir];
		[self copyGenericFiles];
		[self makeControlForPackage:package inDirectory:tweakDir];
		[self copyDEBIANFiles];
	}

	// remove list files now that we're done w them
	NSError *error = NULL;
	[[NSFileManager defaultManager] removeItemAtPath:gFilesToCopy error:&error];
	if(error){
		NSLog(@"[IAmLazyLog] Failed to delete %@! Error: %@", gFilesToCopy, error.localizedDescription);
	}

	NSError *error2 = NULL;
	[[NSFileManager defaultManager] removeItemAtPath:dFilesToCopy error:&error2];
	if(error2){
		NSLog(@"[IAmLazyLog] Failed to delete %@! Error: %@", dFilesToCopy, error2.localizedDescription);
	}

	NSError *error3 = NULL;
	[[NSFileManager defaultManager] removeItemAtPath:targetDir error:&error3];
	if(error3){
		NSLog(@"[IAmLazyLog] Failed to delete %@! Error: %@", targetDir, error3.localizedDescription);
	}
}

-(void)makeSubDirectories:(NSArray *)directories inDirectory:(NSString *)tweakDir{
	for(NSString *dir in directories){
		NSString *path = [NSString stringWithFormat:@"%@%@", tweakDir, dir];
		if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
			NSError *error = NULL;
			[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
			if(error){
				NSLog(@"[IAmLazyLog] Failed to create %@! Error: %@", path, error.localizedDescription);
				continue;
			}
		}
	}
}

-(void)copyGenericFiles{
	// have to run as root in order to retain file attributes (ownership, etc)
	[self executeCommandAsRoot:@"copy-generic-files"];
}

-(void)makeControlForPackage:(NSString *)package inDirectory:(NSString *)tweakDir{
	// get info for package
	NSString *output = [self executeCommandWithOutput:[NSString stringWithFormat:@"dpkg-query -s %@", package]];
	NSString *noStatusLine = [output stringByReplacingOccurrencesOfString:@"Status: install ok installed\n" withString:@""];
	NSString *info = [noStatusLine stringByAppendingString:@"\n"]; // ensure final newline (deb will fail to build if missing)

	NSString *debian = [NSString stringWithFormat:@"%@/DEBIAN/", tweakDir];

	// make DEBIAN dir
	if(![[NSFileManager defaultManager] fileExistsAtPath:debian]){
		NSError *error = NULL;
		[[NSFileManager defaultManager] createDirectoryAtPath:debian withIntermediateDirectories:YES attributes:nil error:&error];
		if(error){
			NSLog(@"[IAmLazyLog] Failed to create %@! Error: %@", debian, error.localizedDescription);
			return;
		}
	}

	// write info to file
	NSData *data = [info dataUsingEncoding:NSUTF8StringEncoding];
	NSString *control = [debian stringByAppendingPathComponent:@"control"];
	[[NSFileManager defaultManager] createFileAtPath:control contents:data attributes:nil];
}

-(void)copyDEBIANFiles{
	// have to copy as root in order to retain file attributes (ownership, etc)
	[self executeCommandAsRoot:@"copy-debian-files"];
}

-(void)buildDebs{
	// have to run as root for some packages to be built correctly (e.g., sudo, openssh-client, etc)
	// if this isn't done as root, said packages will be corrupt and produce the error:
	// "unexpected end of file in archive member header in packageName.deb" upon extraction/installation
	[self executeCommandAsRoot:@"build-debs"];
}

-(void)makeBootstrapFile{
	NSString *bootstrap = @"bingner_elucubratus";
	if([[NSFileManager defaultManager] fileExistsAtPath:@"/.procursus_strapped"]){
		bootstrap = @"procursus";
	}

	NSString *file = [NSString stringWithFormat:@"%@.made_on_%@", tmpDir, bootstrap];
	[[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
}

-(void)makeTarballWithFilter:(BOOL)filter{
	// get current timestamp
	NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init]; 
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	// or @"yyyy-MM-dd hh:mm:ss a" if you prefer the time with AM/PM 
	NSString *currentDate = [dateFormatter stringFromDate:[NSDate date]];

	// craft new backup name
	NSString *backupName;
	if(filter) backupName = [NSString stringWithFormat:@"IAmLazy-%@.tar.gz", currentDate];
	else backupName = [NSString stringWithFormat:@"IAmLazy-%@u.tar.gz", currentDate];

	// make tarball
	// ensure file structure is ONLY me.lightmann.iamlazy/ not /var/tmp/me.lightmann.iamlazy/
	// having --strip-components=2 on the restore end breaks compatibility w older backups
	[self executeCommand:[NSString stringWithFormat:@"cd /var/tmp && tar -czf %@%@ me.lightmann.iamlazy/ --remove-files \\;", backupDir, backupName]];

	// confirm the backup now exists where expected
	[self verifyBackup:backupName];
}

-(void)verifyBackup:(NSString *)backupName{
	NSString *path = [NSString stringWithFormat:@"%@%@", backupDir, backupName];
	if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
		NSString *reason = [NSString stringWithFormat:@"%@ DNE!", path];
		[self popErrorAlertWithReason:reason];
		return;
	}
}

-(NSString *)getDuration{
	NSTimeInterval duration = [self.endTime timeIntervalSinceDate:self.startTime];
	return [NSString stringWithFormat:@"%.02f", duration];
}

#pragma mark Restore

-(void)restoreFromBackup:(NSString *)backupName{
	// reset errors
	[self setEncounteredError:NO];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"null"];

	// check for backup dir
	if(![[NSFileManager defaultManager] fileExistsAtPath:backupDir]){
		NSString *reason = @"The backup dir does not exist!";
		[self popErrorAlertWithReason:reason];
		return;
	}

	// check for backups
	int backupCount = [[self getBackups] count];
	if(!backupCount){
		NSString *reason = @"No backups were found!";
		[self popErrorAlertWithReason:reason];
		return;
	}

	// check for target backup
	if(![[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@%@", backupDir, backupName]]){
		NSString *reason = [NSString stringWithFormat:@"The target backup -- %@ -- could not be found!", backupName];
		[self popErrorAlertWithReason:reason];
		return;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"0"];

	// check for old tmp files
	if([[NSFileManager defaultManager] fileExistsAtPath:tmpDir]){
		[self cleanupTmp];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"0.7"];
	[self unpackArchive:backupName];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"1"];

	// make log dir if it doesn't exist already
	if(![[NSFileManager defaultManager] fileExistsAtPath:logDir]){
		NSError *error = NULL;
		[[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:&error];
		if(error){
			NSString *reason = [NSString stringWithFormat:@"Failed to create %@. \n\nError: %@", logDir, error.localizedDescription];
			[self popErrorAlertWithReason:reason];
			return;
		}
	}

	BOOL compatible = YES;
	if([backupName containsString:@"u.tar"]){
		compatible = [self verifyBootstrap];
	}

	if(compatible){
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"1.7"];
		[self installDebs];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateProgress" object:@"2"];
	}

	[self cleanupTmp];
}

-(void)unpackArchive:(NSString *)backupName{
	[self executeCommand:[NSString stringWithFormat:@"tar -xf %@%@ -C /var/tmp", backupDir, backupName]];
}

-(BOOL)verifyBootstrap{
	NSString *bootstrap = @"bingner_elucubratus";
	NSString *oppBootstrap = @"procursus";
	if([[NSFileManager defaultManager] fileExistsAtPath:@"/.procursus_strapped"]){
		bootstrap = @"procursus";
		oppBootstrap = @"bingner_elucubratus";
	}

	if(![[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@.made_on_%@", tmpDir, bootstrap]]){
		NSString *reason = [NSString stringWithFormat:@"The backup you're trying to restore from was made for jailbreaks running the %@ bootstrap. \n\nYour current jailbreak is using %@!", oppBootstrap, bootstrap];
		[self popErrorAlertWithReason:reason];
		return NO;
	}

	return YES;
}

-(void)installDebs{
	// installing via apt/dpkg requires root
	[self executeCommandAsRoot:@"install-debs"];
}

#pragma mark General

-(void)cleanupTmp{
	// has to be done as root since some files have root ownership
	[self executeCommandAsRoot:@"cleanup-tmp"];
}

-(NSArray *)getBackups{
	NSMutableArray *backups = [NSMutableArray new];

	NSError *readError = NULL;
	NSArray *backupDirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDir error:&readError];
	if(readError){
		NSLog(@"[IAmLazyLog] Failed to get contents of %@! Error: %@", backupDir, readError.localizedDescription);
		return [NSArray new];
	}

	for(NSString *filename in backupDirContents){
		if([filename containsString:@"IAmLazy-"] && [filename containsString:@".tar.gz"]){
			[backups addObject:filename];
		}
	}

	// sort backups (https://stackoverflow.com/a/43096808)
	NSSortDescriptor *nameDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES comparator:^NSComparisonResult(id obj1, id obj2) {
		return - [(NSString *)obj1 compare:(NSString *)obj2 options:NSNumericSearch]; // note: "-" == NSOrderedDescending
	}];
	NSArray *sortedBackups = [backups sortedArrayUsingDescriptors:@[nameDescriptor]];

	return sortedBackups;
}

// Note: using the desired binaries (e.g., rm, rsync) as the launch path occasionally causes a crash (EXC_CORPSE_NOTIFY) because abort() was called???
// to fix this, switched the launch path to bourne shell and, voila, no crash!
-(void)executeCommand:(NSString *)cmd{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/bin/sh"];
	[task setArguments:@[@"-c", cmd]];
	[task launch];
	[task waitUntilExit];
}

-(NSString *)executeCommandWithOutput:(NSString *)cmd{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/bin/sh"];
	[task setArguments:@[@"-c", cmd]];

	NSPipe *pipe = [NSPipe pipe];
	[task setStandardOutput:pipe];

	[task launch];

	NSFileHandle *handle = [pipe fileHandleForReading];
	NSData *data = [handle readDataToEndOfFile];
	[handle closeFile];

	NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

	return output;
}

// made one for AndSoAreYou just for consistency. This isn't really necessary
-(void)executeCommandAsRoot:(NSString *)cmd{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/libexec/iamlazy/AndSoAreYou"];
	[task setArguments:@[cmd]];
	[task launch];
	[task waitUntilExit];
}

-(void)popErrorAlertWithReason:(NSString *)reason{
	[self setEncounteredError:YES];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IAmLazy Error:" message:reason preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction *okay = [UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
		[self.rootVC dismissViewControllerAnimated:YES completion:nil];
	}];

	[alert addAction:okay];

	[self.rootVC dismissViewControllerAnimated:YES completion:^ {
		[self.rootVC presentViewController:alert animated:YES completion:nil];
	}];

	NSLog(@"[IAmLazyLog] %@", [reason stringByReplacingOccurrencesOfString:@"\n" withString:@""]);
}

@end
