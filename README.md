
# [levee]

[![builds.sr.ht status](https://builds.sr.ht/~andreafeletto/levee/commits/main.svg)](https://builds.sr.ht/~andreafeletto/levee/commits/main)

levee is a statusbar for the [river] wayland compositor, written in [zig]
without any UI toolkit. It currently provides full support for workspace tags
and displays pulseaudio volume, battery capacity and screen brightness.

## Build

```
git clone --recurse-submodules https://git.sr.ht/~andreafeletto/levee
cd levee
zig build --prefix ~/.local install
```

## Usage

Add the following toward the end of `$XDG_CONFIG_HOME/river/init`:

```
riverctl spawn levee pulse backlight battery
```

## Dependencies

* [zig] 0.9.0
* [wayland] 1.20.0
* [pixman] 0.40.0
* [fcft] 3.0.1
* [libpulse] 15.0

## Contributing

You are welcome to send patches to the [mailing list] or report bugs on the
[issue tracker].

If you aren't familiar with `git send-email`, you can use the [web interface]
or learn about it following this excellent [tutorial].

[levee]: https://sr.ht/~andreafeletto/levee
[river]: https://github.com/riverwm/river/
[zig]: https://ziglang.org/
[wayland]: https://wayland.freedesktop.org/
[pixman]: http://pixman.org/
[fcft]: https://codeberg.org/dnkl/fcft/
[libpulse]: https://www.freedesktop.org/wiki/Software/PulseAudio/
[mailing list]: https://lists.sr.ht/~andreafeletto/public-inbox
[issue tracker]: https://todo.sr.ht/~andreafeletto/levee
[web interface]: https://git.sr.ht/~andreafeletto/levee/send-email
[tutorial]: https://git-send-email.io
