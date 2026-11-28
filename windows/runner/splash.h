#ifndef RUNNER_SPLASH_H_
#define RUNNER_SPLASH_H_

// The start screen (Anicel's way): the mark and the name, no ground, in a
// transparent window half the monitor's short side tall, shown until the
// first Flutter frame. The picture is the app's own asset
// (assets/app_art/splash.png, drawn by tool/app_art).
void ShowSplash();
void CloseSplash();

#endif  // RUNNER_SPLASH_H_
