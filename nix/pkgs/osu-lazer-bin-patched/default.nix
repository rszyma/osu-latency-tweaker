{
  lib,
  SDL2,
  sdl3,
  alsa-lib,
  appimageTools,
  autoPatchelfHook,
  fetchurl,
  ffmpeg_4,
  icu,
  libkrb5,
  lttng-ust,
  makeWrapper,
  numactl,
  openssl,
  stdenvNoCC,
  vulkan-loader,
  openxr-loader,
  patchelfUnstable,
  writeText,
  callPackage,
  nativeWayland ? true,
  releaseStream ? "lazer",
  basscallwrap ? (callPackage ../basscallwrap/package.nix { }),
  _info ? (builtins.fromJSON (builtins.readFile ./info.json)).${releaseStream},
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "osu-lazer-bin";
  version = _info.version;

  src = appimageTools.extract {
    version = finalAttrs.version;
    pname = "osu.AppImage";
    src = fetchurl {
      url = "https://github.com/ppy/osu/releases/download/${finalAttrs.version}/osu.AppImage";
      hash = _info.hash;
    };
  };

  buildInputs = [
    SDL2
    sdl3
    alsa-lib
    ffmpeg_4
    icu
    libkrb5
    lttng-ust
    numactl
    openssl
    vulkan-loader
    openxr-loader
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall

    install -d $out/bin $out/lib
    install osu.png $out/osu.png
    cp -r usr/bin $out/lib/osu

    makeWrapper $out/lib/osu/osu\! $out/bin/osu-lazer \
      ${lib.optionalString nativeWayland "--set-default SDL_VIDEODRIVER wayland"} \
      --set OSU_EXTERNAL_UPDATE_PROVIDER "1" \
      --set OSU_EXTERNAL_UPDATE_STREAM "${releaseStream}" \
      --set vblank_mode "0" \
      --suffix LD_LIBRARY_PATH : "${lib.makeLibraryPath finalAttrs.buildInputs}"

    runHook postInstall
  '';

  fixupPhase = ''
    runHook preFixup

    # Replace BASS_Init symbol with our wrapper from basscallwrap.so.
    ${patchelfUnstable}/bin/patchelf \
      --rename-dynamic-symbols ${writeText "libbass_sym_overrides" "BASS_Init BASS_Init__orig\n"} \
      --add-needed ${basscallwrap}/lib/basscallwrap.so \
      $out/lib/osu/libbass.so

    # These are required on wayland, prob ones for X11 are required too.
    # + libudev apparently needed (if u run sdl verbose log it tries to open it all the time)
    patchelf \
      --add-needed libwayland-client.so \
      --add-needed libxkbcommon.so \
      --add-needed libEGL.so \
      --add-needed libasound.so \
      --add-needed libudev.so \
      $out/lib/osu/libSDL2.so

    # Patch for x11. Not sure if all of these are needed.
    patchelf \
      --add-needed libX11.so \
      --add-needed libXext.so \
      --add-needed libXcursor.so \
      --add-needed libXi.so \
      --add-needed libXfixes.so \
      --add-needed libXrandr.so \
      --add-needed libXss.so \
      --add-needed libXrender.so \
      --add-needed libdecor-0.so \
      --add-needed libxcb.so \
      --add-needed libXau.so \
      --add-needed libXdmcp.so \
      $out/lib/osu/libSDL2.so

    # testing other deps, not sure if needed.
    patchelf \
      --add-needed librt.so \
      $out/lib/osu/libSDL2.so

    runHook postFixup
  '';

  meta = {
    description = "Rhythm is just a *click* away";
    longDescription = "osu-lazer extracted from the official AppImage to retain multiplayer support, and patched to allow setting custom latency";
    homepage = "https://osu.ppy.sh";
    license = with lib.licenses; [
      mit
      cc-by-nc-40
      unfreeRedistributable # osu-framework contains libbass.so in repository
    ];
    mainProgram = "osu-lazer";
    passthru.updateScript = ./update.sh;
    platforms = [ "x86_64-linux" ];
  };
})
