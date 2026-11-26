"""Patch audio_service's iOS plugin: only publish Now Playing while backgrounded.

iOS renders the Now Playing entry in the Dynamic Island. audio_service publishes
it as soon as playback starts, so PiliPlus shows an island entry even while the
video is on screen. Publishing only while the app is in the background matches
how Apple Music behaves, and keeps the entry alive for lock-screen controls.

Runs on the pub cache copy before `flutter build` (CocoaPods copies it at
`pod install`). Idempotent: re-running finds the marker and does nothing.
"""
import os
import re
import sys

MARKER = "PiliPlusIsAppForeground"

HELPER = r'''
// ---- PiliPlus patch: Now Playing only while backgrounded ----
static BOOL PiliPlusPipActive = NO;

static BOOL PiliPlusIsAppForeground(void) {
#if TARGET_OS_IPHONE
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                return YES;
            }
        }
        return NO;
    }
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
#else
    return NO;
#endif
}

'''

NOTIFY = r'''            // PiliPlus patch: refresh Now Playing when the app moves between
            // foreground and background, so the island entry appears only while
            // the app is not on screen.
#if TARGET_OS_IPHONE
            [[NSNotificationCenter defaultCenter] addObserver:instance
                                                     selector:@selector(piliPlusAppStateChanged:)
                                                         name:UIApplicationDidBecomeActiveNotification
                                                       object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:instance
                                                     selector:@selector(piliPlusAppStateChanged:)
                                                         name:UIApplicationDidEnterBackgroundNotification
                                                       object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:instance
                                                     selector:@selector(piliPlusAppStateChanged:)
                                                         name:UIApplicationWillResignActiveNotification
                                                       object:nil];
#endif
            // PiP is on screen: its own restore button is the way back, and the
            // Now Playing card cannot be opened for sideloaded builds.
            [[NSNotificationCenter defaultCenter] addObserver:instance
                                                     selector:@selector(piliPlusPipStateChanged:)
                                                         name:@"com.example.piliplus/pipState"
                                                       object:nil];
'''

METHOD = r'''
// PiliPlus patch
- (void)piliPlusAppStateChanged:(NSNotification *)notification {
    [self updateNowPlayingInfo];
}

// PiliPlus patch: PiP state comes from PipPlugin (app module) via
// NotificationCenter because the two live in different pods/modules.
- (void)piliPlusPipStateChanged:(NSNotification *)notification {
    PiliPlusPipActive = [notification.userInfo[@"active"] boolValue];
    [self updateNowPlayingInfo];
}

'''

OLD_PUBLISH = '''    if (updated) {
        //NSLog(@"### updating nowPlayingInfo");
        center.nowPlayingInfo = nowPlayingInfo;
    }
'''

NEW_PUBLISH = '''    if (PiliPlusIsAppForeground() || PiliPlusPipActive) {
        // App on screen, or a PiP window is showing: drop the Now Playing entry.
        // The Dynamic Island card cannot be opened on sideloaded iOS 27.3 builds,
        // so while PiP offers a working return button the card is misleading.
        center.nowPlayingInfo = nil;
        if (@available(iOS 13.0, macOS 10.12.2, *)) {
            center.playbackState = MPNowPlayingPlaybackStateStopped;
        }
    } else if (updated || center.nowPlayingInfo == nil) {
        //NSLog(@"### updating nowPlayingInfo");
        center.nowPlayingInfo = nowPlayingInfo;
    }
'''


def find_plugin(root):
    hits = []
    for base, _dirs, files in os.walk(root):
        if "AudioServicePlugin.m" in files:
            hits.append(os.path.join(base, "AudioServicePlugin.m"))
    return hits


def patch(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    if MARKER in src:
        return "already patched"
    if OLD_PUBLISH not in src:
        return "anchor not found (publish block)"
    src = src.replace(OLD_PUBLISH, NEW_PUBLISH, 1)

    # helper right after the last static declaration (before @implementation)
    impl = "@implementation AudioServicePlugin"
    if impl not in src:
        return "anchor not found (@implementation)"
    src = src.replace(impl, HELPER + impl, 1)

    # observers inside the one-time init
    anchor = "            [registrar addMethodCallDelegate:instance channel:handlerChannel];\n"
    if anchor not in src:
        return "anchor not found (registrar init)"
    src = src.replace(anchor, anchor + NOTIFY, 1)

    # method before updateControls
    ctrl = "- (void) updateControls {"
    if ctrl not in src:
        return "anchor not found (updateControls)"
    src = src.replace(ctrl, METHOD + ctrl, 1)

    if "#import <UIKit/UIKit.h>" not in src:
        src = src.replace(
            '#import <MediaPlayer/MediaPlayer.h>',
            '#import <MediaPlayer/MediaPlayer.h>\n#if TARGET_OS_IPHONE\n#import <UIKit/UIKit.h>\n#endif',
            1,
        )

    open(path, "w", encoding="utf-8", newline="").write(src)
    return "patched"


def main():
    roots = sys.argv[1:] or [os.path.expanduser("~/.pub-cache")]
    found = []
    for root in roots:
        if os.path.isdir(root):
            found.extend(find_plugin(root))
    if not found:
        print("audio_service plugin source not found under:", roots)
        return 1
    for p in found:
        print(f"{patch(p)}: {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
