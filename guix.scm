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

;; Custom version of the pixman package which does not enable gnuplot
;; output. Otherwise, creek constantly writes gnuplot input to stderr.
;;
;; See https://issues.guix.gnu.org/69962
(define pixman-no-gnuplot
  (package
    (inherit pixman)
    (arguments
      `(#:configure-flags
        (list
          "--disable-static"
          "--enable-timers")))))

(package
  (name "creek")
  (version "0.3.0")
  (source (local-file "." "git-checkout"
                      #:recursive? #t))
  (build-system zig-build-system)
  (arguments
    (list
      #:zig-release-type "safe"
      #:tests? #f))
  (native-inputs
    (list
      pixman-no-gnuplot
      fcft
      pkg-config
      wayland
      wayland-protocols
      zig))
  (home-page "https://github.com/nmeum/creek")
  (synopsis "Malleable and minimalist status bar for the River compositor.")
  (description "")
  (license license:expat))
