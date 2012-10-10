//
//  PBGitSHA.m
//  GitX
//
//  Created by BrotherBard on 3/28/10.
//  Copyright 2010 BrotherBard. All rights reserved.
//

#import "PBGitSHA.h"
#import "git2/errors.h"
#import "git2/oid.h"


@interface PBGitSHA ()

- (id)initWithOID:(git_oid)g_oid;

@end


@implementation PBGitSHA


@synthesize oid;
@synthesize string;


+ (PBGitSHA *)shaWithOID:(git_oid)oid
{
	return [[PBGitSHA alloc] initWithOID:oid];
}


+ (PBGitSHA *)shaWithString:(NSString *)shaString
{
	git_oid oid;
	int err = git_oid_fromstr(&oid, [shaString UTF8String]);
	if (err == GITERR_INVALID)
		return nil;

	return [self shaWithOID:oid];
}


+ (PBGitSHA *)shaWithCString:(const char *)shaCString
{
	git_oid oid;
	int err = git_oid_fromstr(&oid, shaCString);
	if (err == GITERR_INVALID)
		return nil;

	return [self shaWithOID:oid];
}


+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}


+ (BOOL)isKeyExcludedFromWebScript:(const char *)name
{
	return NO;
}



#pragma mark -
#pragma mark PBGitSHA

- (id)initWithOID:(git_oid)g_oid
{
	self = [super init];
	if (!self)
		return nil;

	oid = g_oid;

	return self;
}


- (NSString *)string
{
	if (!string) {
		char *hex = git_oid_allocfmt(&oid);
		if (hex == NULL)
			return nil;
		string = [NSString stringWithUTF8String:hex];
		free(hex);
	}

	return string;
}


- (BOOL)isEqual:(id)otherSHA
{
	if (self == otherSHA)
		return YES;

	git_oid other_oid = [(PBGitSHA *)otherSHA oid];
	return git_oid_cmp(&oid, &other_oid) == 0;
}


- (BOOL)isEqualToOID:(git_oid)other_oid
{
	return git_oid_cmp(&oid, &other_oid) == 0;
}


- (NSUInteger)hash
{
	NSUInteger hash;
	memcpy(&hash, &(oid.id), sizeof(NSUInteger));

	return hash;
}


- (NSString *)description
{
	return [self string];
}



#pragma mark <NSCopying>

- (id)copyWithZone:(NSZone *)zone
{
	git_oid oidCopy;
	git_oid_cpy(&oidCopy, &oid);
    PBGitSHA *copy = [[[self class] allocWithZone:zone] initWithOID:oidCopy];

	return copy;
}

@end
