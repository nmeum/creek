(use-modules (guix packages)
             (gnu packages gdb)
             (gnu packages zig)
             (gnu packages linux)
             (gnu packages freedesktop)
             (gnu packages xdisorg)
             (gnu packages pkg-config)
             (gnu packages fontutils)
             (gnu packages textutils))

(define fcft-utf8
  (package
    (inherit fcft)
    (native-inputs
      (modify-inputs (package-native-inputs fcft)
                     (prepend utf8proc)))))

(packages->manifest
  (list
    gdb
    pixman
    fcft-utf8
    pkg-config
    eudev
    wayland
    wayland-protocols
    zig))
