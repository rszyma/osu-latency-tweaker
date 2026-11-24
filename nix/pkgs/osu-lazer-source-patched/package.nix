# osu-lazer built from local osu and osu-framework sources, with the same libbass patch as
# osu-lazer-bin-patched. Adapted from nixpkgs' osu-lazer.
#
# It carries the version of the release it is based on, so osu treats it as a deployed build
# (no "development build" banner). Crash reports to ppy stay off, as the code differs from that
# release. The server does not know its executable hash, so it does not request score
# submission or connect to the realtime servers (spectating, multiplayer, online presence).
# OSU_DISABLE_SCORE_SUBMISSION=0 and OSU_DISABLE_REALTIME=0 try anyway.
# It uses the same data directory as the release.
{
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  runCommand,
  makeWrapper,
  alsa-lib,
  icu,
  krb5,
  lttng-ust,
  numactl,
  openssl,
  libglvnd,
  libxkbcommon,
  libdecor,
  wayland,
  libx11,
  libxext,
  libxcursor,
  libxi,
  libxfixes,
  libxrandr,
  libxscrnsaver,
  libxrender,
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

    # The realtime servers (spectator, multiplayer, metadata) reject an unknown executable hash too,
    # and osu posts "Realtime online functionality is not supported" for each rejected call.
    # Do not connect to them, as for an API without realtime support.
    substituteInPlace osu/osu.Game/Online/API/APIAccess.cs \
      --replace-fail 'new HubClientConnector(clientName, endpoint, this, versionHash);' \
                     'System.Environment.GetEnvironmentVariable("OSU_DISABLE_REALTIME") == "1" ? null : new HubClientConnector(clientName, endpoint, this, versionHash);'
  '';

  projectFile = "osu/osu.Desktop/osu.Desktop.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;

  # Like the release: self-contained, with the .NET runtime version of osu 2026.1117.0.
  selfContainedBuild = true;
  dotnetFlags = [
    "-p:RuntimeFrameworkVersion=10.0.15"
    "-p:Version=${osuVersion}"
    # osu shows this up to the "+".
    "-p:InformationalVersion=${osuVersion}-lazer+source"
  ];

  nativeBuildInputs = [ makeWrapper ];

  # The bundled SDL3 (ppy's build, as in the release) loads the display libraries at runtime.
  runtimeDeps = [
    alsa-lib
    icu
    krb5
    lttng-ust
    numactl
    openssl
    libglvnd
    libxkbcommon
    libdecor
    wayland
    libx11
    libxext
    libxcursor
    libxi
    libxfixes
    libxrandr
    libxscrnsaver
    libxrender
    udev
    vulkan-loader
  ];

  executables = [ "osu!" ];

  postFixup = ''
    # A gen0 budget of 256 MB, so that the little garbage made during gameplay (about 0.1 MB/s)
    # does not cause gen0 collections, each a pause of all threads, within a map.
    # Update (and with an unlimited frame limiter, draw) frames at up to 2000 Hz, so that each update frame
    # takes newer mouse input (input-latency branch of osu-framework).
    wrapProgram $out/bin/osu! \
      ${lib.optionalString nativeWayland "--set-default SDL_VIDEODRIVER wayland"} \
      --set OSU_EXTERNAL_UPDATE_PROVIDER 1 \
      --set OSU_DISABLE_ERROR_REPORTING 1 \
      --set-default OSU_DISABLE_SCORE_SUBMISSION 1 \
      --set-default OSU_DISABLE_REALTIME 1 \
      --set vblank_mode 0 \
      --set-default DOTNET_GCgen0size 0x10000000 \
      --set-default OSU_FRAMEWORK_MAXIMUM_FPS 2000
    ln -s osu! $out/bin/osu-lazer

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
