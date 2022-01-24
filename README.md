
# levee

levee is a statusbar for the [river](https://github.com/riverwm/river/) wayland
compositor, written in [zig](https://ziglang.org/) without any UI toolkit.

It is still in early development.

## Build

```
git clone --recurse-submodules https://git.sr.ht/~andreafeletto/levee
cd levee
zig build -Drelease-safe --prefix ~/.local install
```

## Usage

```
levee
```

## Dependencies

* [zig](https://ziglang.org/) 0.9.0
* [wayland](https://wayland.freedesktop.org/)
* [pixman](http://pixman.org/)
* [fcft](https://codeberg.org/dnkl/fcft)
