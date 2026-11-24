# osu-lazer built from local osu and osu-framework sources, with the same libbass patch as
# osu-lazer-bin-patched. Adapted from nixpkgs' osu-lazer.
#
# It carries the version of the release it is based on, so osu treats it as a deployed build
# (no "development build" banner). Crash reports to ppy stay off, as the code differs from that
# release. The server does not know its executable hash, so it does not request score
# submission (OSU_DISABLE_SCORE_SUBMISSION=0 tries anyway), and multiplayer does not work.
# It uses the same data directory as the release.
{
  lib,
  stdenvNoCC,
  buildDotnetModule,
  dotnetCorePackages,
  runCommand,
  makeWrapper,
  ffmpeg,
  alsa-lib,
  SDL2,
  sdl3,
  lttng-ust,
  numactl,
  libglvnd,
  libxi,
  udev,
  vulkan-loader,
  patchelfUnstable,
  writeText,
  callPackage,
  osuSrc,
  osuFrameworkSrc,
  nativeWayland ? true,
  # The osu release which osuSrc is based on.
  osuVersion ? "2026.1117.0",
  basscallwrap ? (callPackage ../basscallwrap/package.nix { }),
}:

buildDotnetModule (finalAttrs: {
  pname = "osu-lazer";
  version = "${osuVersion}-source";

  # osu.Game references the framework project instead of its NuGet package.
  src = runCommand "osu-with-framework-src" { } ''
    mkdir $out
    cp -r ${osuSrc} $out/osu
    cp -r ${osuFrameworkSrc} $out/osu-framework
  '';

  postPatch = ''
    chmod -R u+w .
    sed -i -E 's|<PackageReference Include="ppy.osu.Framework" Version="[^"]*" */>|<ProjectReference Include="../../osu-framework/osu.Framework/osu.Framework.csproj"/>|' \
      osu/osu.Game/osu.Game.csproj
    grep -q 'osu.Framework.csproj' osu/osu.Game/osu.Game.csproj

    # The server rejects score tokens for an unknown executable hash, and osu posts a notification
    # for that in each play. Skip the request, as osu does for locally modified beatmaps.
    substituteInPlace osu/osu.Game/Screens/Play/SoloPlayer.cs \
      --replace-fail 'if (beatmapId <= 0)' \
                     'if (beatmapId <= 0 || System.Environment.GetEnvironmentVariable("OSU_DISABLE_SCORE_SUBMISSION") == "1")'
  '';

  projectFile = "osu/osu.Desktop/osu.Desktop.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;

  dotnetFlags = [
    "-p:Version=${osuVersion}"
    # osu shows this up to the "+".
    "-p:InformationalVersion=${osuVersion}-lazer+source"
  ];

  nativeBuildInputs = [ makeWrapper ];

  runtimeDeps = [
    ffmpeg
    alsa-lib
    SDL2
    sdl3
    lttng-ust
    numactl
    libglvnd
    libxi
    udev
    vulkan-loader
  ];

  executables = [ "osu!" ];

  postFixup = ''
    wrapProgram $out/bin/osu! \
      ${lib.optionalString nativeWayland "--set-default SDL_VIDEODRIVER wayland"} \
      --set OSU_EXTERNAL_UPDATE_PROVIDER 1 \
      --set OSU_DISABLE_ERROR_REPORTING 1 \
      --set-default OSU_DISABLE_SCORE_SUBMISSION 1 \
      --set vblank_mode 0
    ln -s osu! $out/bin/osu-lazer

    ln -sft $out/lib/${finalAttrs.pname} ${SDL2}/lib/libSDL2${stdenvNoCC.hostPlatform.extensions.sharedLibrary}
    ln -sft $out/lib/${finalAttrs.pname} ${sdl3}/lib/libSDL3${stdenvNoCC.hostPlatform.extensions.sharedLibrary}

    # Replace BASS_Init symbol with our wrapper from basscallwrap.so.
    ${patchelfUnstable}/bin/patchelf \
      --rename-dynamic-symbols ${writeText "libbass_sym_overrides" "BASS_Init BASS_Init__orig\n"} \
      --add-needed ${basscallwrap}/lib/basscallwrap.so \
      $out/lib/${finalAttrs.pname}/libbass.so
  '';

  meta = {
    description = "osu-lazer built from local osu and osu-framework sources, with patched libbass";
    homepage = "https://osu.ppy.sh";
    license = with lib.licenses; [
      mit
      cc-by-nc-40
      unfreeRedistributable # osu-framework contains libbass.so in repository
    ];
    mainProgram = "osu-lazer";
    platforms = [ "x86_64-linux" ];
  };
})
