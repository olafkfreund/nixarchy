Screenshots of the running desktop, captured with ../capture-screenshots.sh.
They need a graphical VM: with -display none nothing consumes the compositor's
frames and grim blocks forever.

17-plugins-menu.jpg and 18-plugins-bar.jpg are the exception: they come from
`nix build .#checks.x86_64-linux.plugin`, which installs two real third-party
plugins and screenshots the result. That check runs headless -- its frames come
from qemu's screendump rather than grim -- and it is the only place where two
plugins are installed and enabled at once, which is what the bar strips show.

19-trigger.jpg, 20-ask.jpg and 21-setup-agent.jpg come from `nix build .#demo`
for the same reason -- it drives the menu by route and captures through qemu's
screendump, so it needs no display. 20-ask.jpg required setting a default agent
first: the Ask group is hidden until one is chosen.

22-boot-splash.jpg and 23-installer-welcome.jpg are the ISO rather than the
desktop, from `nix build .#iso-net` booted under qemu with `-vga std -display
none` and captured through the monitor's `screendump`. The splash is on screen
for about five seconds, so the capture is a loop rather than one shot; the
frame kept is the one where plymouth has drawn and nothing has scrolled over
it. 23 is the frame the same run ends on, which is why the two agree about
what the console looks like.
