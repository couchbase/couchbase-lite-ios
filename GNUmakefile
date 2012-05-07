# TouchDB Makefile for GNUstep

# Include the common variables defined by the Makefile Package
include $(GNUSTEP_MAKEFILES)/common.make

# Build a simple Objective-C program
FRAMEWORK_NAME = TouchDB

# The Objective-C files to compile
TouchDB_OBJC_FILES = \
    Source/TDDatabase.m \
    Source/TDDatabase+Replication.m \
    Source/TDDatabase+Attachments.m \
    Source/TDDatabase+Insertion.m \
    Source/TDDatabase+LocalDocs.m \
    Source/TDAttachment.m \
    Source/TDBody.m \
    Source/TDRevision.m \
    Source/TDView.m \
    Source/TDDatabaseManager.m \
    Source/TDServer.m \
    Source/TDBlobStore.m \
    \
    Source/TDRouter.m \
    Source/TDRouter+Handlers.m \
    Source/TDURLProtocol.m \
    Source/TDC.m \
    \
    Source/TDReplicator.m \
    Source/TDPuller.m \
    Source/TDPusher.m \
    Source/TDReplicatorManager.m \
    Source/TDRemoteRequest.m \
    Source/TDMultipartDocumentReader.m \
    Source/TDMultipartDownloader.m \
    Source/TDMultipartReader.m \
    Source/TDMultipartUploader.m \
	Source/TDMultiStreamWriter.m \
    Source/TDMultipartWriter.m \
    Source/TDReachability_Stubs.m \
    \
    Source/TDBatcher.m \
    Source/TDCanonicalJSON.m \
    Source/TDCollateJSON.m \
    Source/TDGNUstep.m \
    Source/TDBase64.m \
    Source/TDJSON.m \
    Source/TDMisc.m \
    Source/TDSequenceMap.m \
    Source/TDStatus.m \
    \
    Source/TDBlobStore_Tests.m \
    Source/TDDatabase_Tests.m \
    Source/TDReplicator_Tests.m \
    Source/TDRouter_Tests.m \
    Source/TDView_Tests.m \
    Source/ChangeTracker/TDChangeTracker.m \
    Source/ChangeTracker/TDSocketChangeTracker.m \
    Source/ChangeTracker/TDConnectionChangeTracker.m \
    \
    vendor/fmdb/src/FMDatabaseAdditions.m \
    vendor/fmdb/src/FMDatabase.m \
    vendor/fmdb/src/FMResultSet.m \
    \
    vendor/MYUtilities/CollectionUtils.m \
    vendor/MYUtilities/ExceptionUtils.m \
    vendor/MYUtilities/Logging.m \
    vendor/MYUtilities/MYBlockUtils.m \
    vendor/MYUtilities/Test.m \
    \
    vendor/google-toolbox-for-mac/GTMNSData+zlib.m

    # TEMPORARILY DISABLED:
	#Source/TDMultiStreamWriter.m

TouchDB_HEADER_FILES_DIR = Source
TouchDB_HEADER_FILES = \
	TouchDB.h \
	TDBatcher.h \
	TDBlobStore.h \
	TDBody.h \
	TDDatabase+Attachments.h \
	TDDatabase.h \
	TDDatabase+Insertion.h \
	TDDatabase+LocalDocs.h \
	TDDatabase+Replication.h \
	TDJSON.h \
    TDPuller.h \
	TDPusher.h \
    TDReplicator.h \
    TDRevision.h \
    TDRouter.h \
	TDServer.h \
	TDStatus.h \
    TDURLProtocol.h \
	TDView.h \
    TDC.h

TouchDB_INCLUDE_DIRS = \
    -ISource \
    -ISource/ChangeTracker \
    -Ivendor/MYUtilities \
    -Ivendor/google-toolbox-for-mac \
    -Ivendor/fmdb/src

TouchDB_OBJCFLAGS = \
	-include Source/TouchDBPrefix.h
    


TOOL_NAME = TouchTool

TouchTool_OBJC_FILES = Demo-Mac/EmptyGNUstepApp.m

TouchTool_OBJCFLAGS = \
    -include Source/TDGNUstep.h

TouchTool_OBJC_LIBS = \
    -lTouchDB  -LTouchDB.framework \
    -lsqlite3 \
    -lcrypto \
    -luuid

TouchTool_INCLUDE_DIRS = \
    -Ivendor/MYUtilities


OBJCFLAGS = \
	-fblocks \
    -Werror \
    -Wall \
    -DDEBUG=1
    
#LDFLAGS = -v

-include GNUmakefile.preamble

# Include in the rules for making GNUstep frameworks
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble

