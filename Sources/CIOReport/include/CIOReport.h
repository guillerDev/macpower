// CIOReport.h
//
// Reverse-engineered declarations for Apple's private IOReport library
// (/usr/lib/libIOReport.dylib). These symbols are NOT part of the public
// macOS SDK; they are the same API `powermetrics` uses internally to read
// per-subsystem energy counters without requiring root privileges.
//
// Only the subset the app needs is declared here. Signatures were confirmed
// against the exported symbols on this machine (see project notes).
#ifndef CIOREPORT_H
#define CIOREPORT_H

#include <CoreFoundation/CoreFoundation.h>

// Entering an audited region makes Swift import these as native CF types (not
// Unmanaged) and apply the standard CF ownership rules: Create/Copy -> +1,
// Get -> +0. This matches IOReport's actual conventions.
CF_IMPLICIT_BRIDGING_ENABLED

typedef struct IOReportSubscription *IOReportSubscriptionRef;

// Channel discovery ----------------------------------------------------------
CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group,
                                            CFStringRef subgroup,
                                            uint64_t a, uint64_t b, uint64_t c);
void IOReportMergeChannels(CFDictionaryRef dst, CFDictionaryRef src, CFTypeRef nullv);

// Subscription + sampling ----------------------------------------------------
IOReportSubscriptionRef IOReportCreateSubscription(void *allocator,
                                                   CFMutableDictionaryRef desiredChannels,
                                                   CFMutableDictionaryRef *subbedChannels,
                                                   uint64_t channelID,
                                                   CFTypeRef opts);
CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
                                      CFMutableDictionaryRef subbedChannels,
                                      CFTypeRef opts);
CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev,
                                           CFDictionaryRef current,
                                           CFTypeRef opts);

// Per-channel iteration + accessors -----------------------------------------
// The callback returns an int (0 == continue). The second argument to
// IOReportSimpleGetIntegerValue is an out-pointer (pass NULL).
void IOReportIterate(CFDictionaryRef samples, int (^callback)(CFDictionaryRef ch));

CFStringRef IOReportChannelGetGroup(CFDictionaryRef ch);
CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef ch);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef ch);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef ch);
int         IOReportChannelGetFormat(CFDictionaryRef ch);
int64_t     IOReportSimpleGetIntegerValue(CFDictionaryRef ch, int *outSubValue);

// State (residency) channels
int         IOReportStateGetCount(CFDictionaryRef ch);
CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef ch, int index);
int64_t     IOReportStateGetResidency(CFDictionaryRef ch, int index);

CF_IMPLICIT_BRIDGING_DISABLED

#endif /* CIOREPORT_H */
