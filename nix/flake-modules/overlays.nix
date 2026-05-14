{ self, ... }:
{
  flake.overlays.default = import ../../overlays {
    inherit (self) packages;
  };
}
