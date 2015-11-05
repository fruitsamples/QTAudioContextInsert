/*
	File:		ACInsertManager.mm	

	Abstract:	Implements the Audio Context Insert Manager which functions as
	            a factory for creating and configuring Audio Context insert 
				processor objects. At any given time, the ACInsertManager has 
				one processor instance associated with it as the 'current processor'.
				This is the instance that responds to the AC Insert	window controller
				UI. The Audio Context Manager may also have an 'extraction processor'
				instance which is used for insert processing during extraction
				and extraction preview. 
					
	Version:	1.0

	Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
	Computer, Inc. ("Apple") in consideration of your agreement to the
	following terms, and your use, installation, modification or
	redistribution of this Apple software constitutes acceptance of these
	terms.  If you do not agree with these terms, please do not use,
	install, modify or redistribute this Apple software.

	In consideration of your agreement to abide by the following terms, and
	subject to these terms, Apple grants you a personal, non-exclusive
	license, under Apple's copyrights in this original Apple software (the
	"Apple Software"), to use, reproduce, modify and redistribute the Apple
	Software, with or without modifications, in source and/or binary forms;
	provided that if you redistribute the Apple Software in its entirety and
	without modifications, you must retain this notice and the following
	text and disclaimers in all such redistributions of the Apple Software. 
	Neither the name, trademarks, service marks or logos of Apple Computer,
	Inc. may be used to endorse or promote products derived from the Apple
	Software without specific prior written permission from Apple.  Except
	as expressly stated in this notice, no other rights or licenses, express
	or implied, are granted by Apple herein, including but not limited to
	any patent rights that may be infringed by your derivative works or by
	other works in which the Apple Software may be incorporated.

	The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
	MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
	THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
	FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
	OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

	IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
	OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
	SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
	INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
	MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
	AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
	STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
	POSSIBILITY OF SUCH DAMAGE.

	Copyright © 2006 Apple Computer, Inc., All Rights Reserved
*/

#import "ACInsertManager.h"

@implementation ACInsertManager

- (id) init
{
	self = [super init];
	if (self) 
	{
		mMovieDocument = nil;
		mCurrentProcessor = nil;
		mCurrentExtractionProcessor = nil;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:nil];
	}
	return self;
}

- (id) initWithMovieDocument:(MovieDocument *)movieDocument
{
	self = [self init];
	if (self) 
	{
		mMovieDocument = movieDocument;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

#pragma mark 
#pragma mark ---- Getters ----
- (MovieDocument*)document 
{
	return	mMovieDocument;
}
- (AudioUnit)currentAU
{
	return [mCurrentProcessor audioUnit];
}

#pragma mark
#pragma mark ---- Setters ----

// This method is called by the Audio Context Insert Window controller
// whenever a new AU is selected in the AU pop-up menu. We create a
// new Audio Context Insert processor and replace our current instance
// with this new instance.
- (void)createInsertProcessorForAU:(Component)component
{
	
	ACInsertProcessor *processor = [[ACInsertProcessor allocWithZone:[self zone]] initFromAUComponent:(Component)component];
	mCurrentProcessor = processor;			// if mCurrentProcessor was pointing to another processor instance, 
											// that instance will be released in the finalize callback
	mCurrentProcessorComponent = component;
}

// This method is called by the Audio Context Insert Window controller
// whenever the bypass state of the AU is changed in the UI. We set
// this bypass state on the current processor instance which in turn
// sets the state on the AU that it wraps around.
- (void) setInsertBypassed:(UInt32)isBypassed
{
	[mCurrentProcessor setAUBypassed:isBypassed];
}

// This method is called by the Audio Context Insert window controller
// when the insert input layout selection is changed. We set the layout
// on the current processor instance.
- (void) setInsertInputLayout:(AudioChannelLayoutTag)layoutTag
{
	if ([mCurrentProcessor processorIsInitialized]) 
	{		
		// We get here if the in layout is changed without changing the AU
		
		// The current processor is already initialized which means that we've
		// registered the insert. Changing the input layout on the insert, 
		// requires us to throw away the current insert and register with the new
		// layout. So we need to create a new instance of the insert processor. 
		// The current processor instance will be tossed on the finalize callback
		// (called when the current insert is thrown away)
		ACInsertProcessor *newProcessor = [[ACInsertProcessor allocWithZone:[self zone]] initFromAUComponent:mCurrentProcessorComponent];
		// Make a clone of current processor and swap to cloned instance
		[self cloneProcessor:newProcessor fromProcessor:mCurrentProcessor setInputLayout:NO setOutputLayout:NO];
		mCurrentProcessor = newProcessor;
		// We've changed the processor instance without the AC Insert window controller's knowledge.
		// The cocoa view it is hosting is associated with the AU instance of the processor we just replaced.
		// Update the UI to host the view of the new Audio Unit instance.
		[[mMovieDocument acInsertWindowController] showCocoaViewForAU:[mCurrentProcessor audioUnit]];
	} 
	[mCurrentProcessor setInputLayout:layoutTag];

}

// This method is called by the Audio Context Insert window controller
// when the insert output layout selection is changed. We set the layout
// on the current processor instance.
- (void) setInsertOutputLayout:(AudioChannelLayoutTag)layoutTag
{
	OSStatus err = noErr;
	
	if ([mCurrentProcessor processorIsInitialized]) 
	{
		// We get here if the out layout is changed without changing the AU
		// or the in layout.
		
		// The current processor is already initialized which means that we've
		// registered the insert. Changing the output layout on the insert, 
		// requires us to throw away the current insert and register with the new
		// layout. So we need to create a new instance of the insert processor. 
		// The current processor instance will be tossed on the finalize callback
		// (called when the current insert is thrown away)
		ACInsertProcessor *newProcessor = [[ACInsertProcessor allocWithZone:[self zone]] initFromAUComponent:mCurrentProcessorComponent];
		// Make a clone of current processor and swap to cloned instance
		[self cloneProcessor:newProcessor fromProcessor:mCurrentProcessor setInputLayout:YES setOutputLayout:NO];
		mCurrentProcessor = newProcessor;
		// We've changed the processor instance without the AC Insert window controller's knowledge.
		// The cocoa view it is hosting is associated with the AU instance of the processor we just replaced.
		// Update the UI to host the view of the new Audio Unit instance.
		[[mMovieDocument acInsertWindowController] showCocoaViewForAU:[mCurrentProcessor audioUnit]];

	}
	[mCurrentProcessor setOutputLayout:layoutTag];

	// With the output layout set, we've completed the configuration 
	// of our insert processor. Time to register the insert. 
	if ([mCurrentProcessor processorIsInitialized]) 
	{
		err = [self attachUnattachInsert:YES]; // YES => attach
	}
}

	
#pragma mark
#pragma mark ---- Synchronizing with changed UI ----

// This method is called by the Audio Context Insert Window controller to determine whether
// a particular insert in and out layout combination is compatible. We pass on the question
// to our current processor instance which answers this question based on the capabilities of
// the AU that it wraps around.
- (BOOL) insertCanDoInputChannels:(UInt32)inputNumChannels outputNumChannels:(UInt32)outputNumChannels
{
	return ([mCurrentProcessor canDoInputChannels:inputNumChannels outputChannels:outputNumChannels]);

}

// This method is called by the Audio Context Insert Window controller to determine whether
// a particular insert out layout is compatible with the current insert in layout. We pass along the
// question to our current processor instance which answers this question based on the capabilities of
// the AU that it wraps around.
- (BOOL) insertCanDoOutputChannels:(UInt32)numChannels
{
	return ([mCurrentProcessor canDoOutputChannels:numChannels]);
}

// This method is called by the Audio Context Insert Window controller to determine whether
// a particular insert is bypassable, and if it is, what the current bypass state is. We pass along the
// question to our current processor instance which provides the required information based on the AU 
// instance that it is wrapping around.
- (void) insertIsBypassable:(BOOL*)isBypassable currentBypassState:(UInt32*)bypassState
{
	[mCurrentProcessor aUIsBypassable:(BOOL*)isBypassable currentBypassState:(UInt32*)bypassState];
}

#pragma mark
#pragma mark ---- Processor Cloning ----
// This method is called by the Audio Extraction Window controller that wishes to apply an insert during
// movie audio extraction. We create a new insert processor instance for use during extraction, set its
// various parameters and properties so that it is a clone of the current processor instance. Then, we obtain
// registration information from this extraction processor and passed it on to the Audio Extraction window
// controller for use during MovieAudioExtraction configuration.
- (void) createProcessorForExtractionAndGetRegistrationInfo:(QTAudioContextInsertRegistryInfo**)regInfoRef
{
	if ( (![[[mMovieDocument acInsertWindowController] window] isVisible]) ||
		 (![mCurrentProcessor processorIsInitialized]))
	{
		*regInfoRef = NULL;
		return;
	}
	// The Audio Context Insert window is visible, get information from its UI and create
	// insert processor for ourselves, and get necessary registration information
	mCurrentExtractionProcessor = [[ACInsertProcessor allocWithZone:[self zone]] initFromAUComponent:(Component)mCurrentProcessorComponent];
	[self cloneProcessor:mCurrentExtractionProcessor fromProcessor:mCurrentProcessor setInputLayout:YES setOutputLayout:YES];
	*regInfoRef = (QTAudioContextInsertRegistryInfo*)calloc(1, sizeof(QTAudioContextInsertRegistryInfo));
	[mCurrentExtractionProcessor getRegistrationInformation:(*regInfoRef)];
}

// This method is called whenever a new processor instance needs to be created that is
// identical to the current processor instance. We set the values of various properties 
// and parameters of the new instance such that they are the same as the original instance. 
- (void) cloneProcessor:(ACInsertProcessor *)newProcessor 
						fromProcessor:(ACInsertProcessor *)origProcessor 
						setInputLayout:(BOOL)setInputLayout
						setOutputLayout:(BOOL)setOutputLayout
{

	BOOL isBypassable = YES;
	UInt32 isBypassed = 0;
	AudioChannelLayoutTag inLayoutTag, outLayoutTag;
	
	// If original processor is bypassed, make sure the new one is bypassed too
	[origProcessor aUIsBypassable:&isBypassable currentBypassState:&isBypassed];
	if (isBypassable && isBypassed) 
	{
		[newProcessor setAUBypassed:isBypassed];
	}
		
	if (setInputLayout) 
	{
		inLayoutTag = [origProcessor inputLayoutTag];	// get current processor's in layout
		[newProcessor setInputLayout:inLayoutTag];	// set the new processor's in layout to the same as the old one's
	} 
	
	if (setOutputLayout) 
	{
		outLayoutTag = [origProcessor outputLayoutTag];
		[newProcessor setOutputLayout:outLayoutTag];
	}
	
	[newProcessor setAUParametersToThoseOfAU:[origProcessor audioUnit]];
}

#pragma mark
#pragma mark ---- Insert Registration ----
// This method is called to either register or unregister an insert with 
// the movie's audio context. If registering, it creates a new audio context
// for the default device, registers the insert with the new context and then
// sets the new context on the movie. If unregistering it creates a new audio 
// context and sets it on the movie without registering any insert with the context.
- (OSStatus)attachUnattachInsert:(BOOL)attachInsert
{
	OSStatus err = noErr;
	QTAudioContextRef newAudioContext = NULL;
	QTAudioContextInsertRegistryInfo registryInfo;

	// [1] Create an AudioContext 
	err = QTAudioContextCreateForAudioDevice(kCFAllocatorDefault, NULL /*default device*/, NULL, &newAudioContext);
	if (err  || newAudioContext == NULL) 
	{
		NSLog(@"registerInsert : Unable to create audio context for default device (err=%d\tnewAudioContext=%d)", err, newAudioContext);
		goto bail;
	}
	
	if (attachInsert) // If registering, attachInsert==true; If unregistering, attachInsert==false;
	{
		// [2] Register the insert with the Audio Context 
		[mCurrentProcessor getRegistrationInformation:&registryInfo];

		err = QTAudioContextRegisterInsert(newAudioContext, sizeof(registryInfo), &registryInfo);
		if (err) 
		{
			NSLog(@"registerInsert: Unable to register insert (err=%d)", err);
			goto bail;
		}
	}
		
	// [3] Set the AudioContext on the movie
	err = SetMovieAudioContext([[mMovieDocument movie] quickTimeMovie], newAudioContext);
	if (err) 
	{
		NSLog (@"registerInsert: Unable to set audio context on movie (err=%d)", err);
		goto bail;
	} 
	
bail:
	if (newAudioContext) 
	{
		// If err, we  release context
		// If noErr, movie owns the context, so we
		// still release it here
		QTAudioContextRelease (newAudioContext);
		newAudioContext = NULL;
	}
	return err;	
}

#pragma mark
#pragma mark ---- Notification Callback ----
// This notification callback is called whenever a window is being closed.
// If the closing window is an Audio Context Insert Window, we need to
// unregister the insert from the movie's audio context.
- (void)windowWillClose:(NSNotification *)notification
{
	NSWindowController *controller = [[notification object] windowController];
	if ([controller isKindOfClass:[ACInsertWindowController class]]) 
	{
		if ([(ACInsertWindowController*)controller movieDocument] == mMovieDocument) 
		{
			// If this ACInsert window controller that is going away
			// belongs to the same document that we belong to, unhook the
			// insert from the Audio Context before the window goes away
			[self attachUnattachInsert:NO];	//NO => unattach
		}
	}	
}
@end