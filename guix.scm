(use-modules (guix packages)
             ((guix licenses) #:prefix license:)
             (guix gexp)
             (guix build-system zig)
             (gnu packages zig)
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

(package
  (name "creek")
  (version "0.1.3")
  (source (local-file "." "git-checkout"
                      #:recursive? #t))
  (build-system zig-build-system)
  (arguments
    (list
      #:zig-release-type "safe"
      #:tests? #f))
  (native-inputs
    (list
      pixman
      fcft-utf8
      pkg-config
      wayland
      wayland-protocols
      zig))
  (home-page "https://github.com/nmeum/creek")
  (synopsis "A minimalistic and malleable status bar for the River compositor.")
  (description "")
  (license license:expat))
