#import <ApplicationServices/ApplicationServices.h>

CG_EXTERN CGError CGSGetDisplayList(CGDisplayCount maxDisplays,
                                    CGDirectDisplayID *displays,
                                    CGDisplayCount *displayCount);

CG_EXTERN CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef config,
                                             CGDirectDisplayID display,
                                             bool enabled);

AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *identifier);
