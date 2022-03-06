
# levee

levee is a statusbar for the [river] wayland compositor, written in [zig]
without any UI toolkit.
It is still in early development.

## Build

```
git clone --recurse-submodules https://git.sr.ht/~andreafeletto/levee
cd levee
zig build -Drelease-safe --prefix ~/.local install
```

## Usage

Add the following toward the end of `$XDG_CONFIG_HOME/river/init`:

```
riverctl spawn levee
```

## Dependencies

* [zig] 0.9.0
* [wayland] 1.20.0
* [pixman] 0.40.0
* [fcft] 3.0.1

[river]: https://github.com/riverwm/river/
[zig]: https://ziglang.org/
[wayland]: https://wayland.freedesktop.org/
[pixman]: http://pixman.org/
[fcft]: https://codeberg.org/dnkl/fcft/
